// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title ChihuahuaQuest
 * @dev 1日1回報酬受取、手数料によるリセット、およびオンチェーン図鑑機能を備えたゲームコントラクト
 */
contract ChihuahuaQuest is Ownable {
    using ECDSA for bytes32;

    // --- トークン・署名者設定 ---
    IERC20 public immutable chhToken;      // 報酬用CHH
    IERC20 public paymentToken;           // クールダウン解除用 (USDC等)
    address public backendSigner;         // 署名検証用アドレス
    uint256 public resetFee;              // 解除に必要な費用

    // --- 報酬・図鑑データ構造 ---
    struct RewardConfig {
        uint256 chhAmount;
        bool exists;
    }

    mapping(uint256 => RewardConfig) public treasureRewards; // お宝ごとの報酬額
    mapping(address => uint256) public lastClaimDay;        // 最終受取日 (block.timestamp / 1 days)
    mapping(address => uint256) public nonces;              // リプレイ攻撃防止用

    // 図鑑用ストレージ
    mapping(address => mapping(uint256 => uint256)) public userInventory; // player => treasureId => count
    mapping(address => uint256[]) private userOwnedIds;                 // playerが所持しているIDリスト
    mapping(address => mapping(uint256 => bool)) private isIdInList;    // リスト重複登録防止用

    // --- イベント ---
    event SessionCompleted(address indexed player, uint256 totalReward, uint256[] treasureIds, uint256 timestamp);
    event RewardConfigUpdated(uint256 indexed treasureId, uint256 chhAmount);
    event ClaimCooldownReset(address indexed player, uint256 feePaid);
    event PaymentConfigUpdated(address indexed token, uint256 fee);

    constructor(address _chhTokenAddress, address _backendSigner) Ownable(msg.sender) {
        require(_chhTokenAddress != address(0), "Invalid token address");
        chhToken = IERC20(_chhTokenAddress);
        backendSigner = _backendSigner;
    }

    // --- 管理者用関数 ---

    /**
     * @dev 財宝の報酬設定を一括更新（入力値は ether 単位）
     */
    function setTreasureRewardsBatch(uint256[] calldata treasureIds, uint256[] calldata chhAmountsInEther) external onlyOwner {
        require(treasureIds.length == chhAmountsInEther.length, "Mismatched lengths");
        for (uint256 i = 0; i < treasureIds.length; i++) {
            uint256 fullAmount = chhAmountsInEther[i] * 1e18;
            treasureRewards[treasureIds[i]] = RewardConfig(fullAmount, true);
            emit RewardConfigUpdated(treasureIds[i], fullAmount);
        }
    }

    /**
     * @dev 支払い設定（リセット費用）の変更
     */
    function setPaymentConfig(address _tokenAddress, uint256 _fee) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        paymentToken = IERC20(_tokenAddress);
        resetFee = _fee;
        emit PaymentConfigUpdated(_tokenAddress, _fee);
    }

    function setBackendSigner(address _newSigner) external onlyOwner {
        require(_newSigner != address(0), "Invalid signer address");
        backendSigner = _newSigner;
    }

    /**
     * @dev 貯まった支払いトークンを回収
     */
    function withdrawPaymentTokens() external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        if (balance > 0) paymentToken.transfer(owner(), balance);
    }

    // --- メインロジック ---

    /**
     * @dev 報酬の受け取りと図鑑の更新を一括で行う
     */
    function recordGameSession(
        uint256[] calldata treasureIds,
        uint256 nonce,
        bytes calldata signature
    ) external {
        // 1. 日付チェック (JST 9:00 リセット)
        uint256 currentDay = block.timestamp / 1 days;
        require(currentDay > lastClaimDay[msg.sender], "Already claimed today");

        // 2. 署名検証
        require(nonce == nonces[msg.sender], "Invalid nonce");
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, treasureIds, nonce, address(this)));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        require(ECDSA.recover(ethSignedMessageHash, signature) == backendSigner, "Invalid signature");

        // 3. 状態更新
        nonces[msg.sender]++;
        lastClaimDay[msg.sender] = currentDay;

        // 4. 図鑑更新と報酬計算
        uint256 totalReward = 0;
        for (uint256 i = 0; i < treasureIds.length; i++) {
            uint256 tid = treasureIds[i];
            
            // 図鑑データの更新
            userInventory[msg.sender][tid] += 1;
            if (!isIdInList[msg.sender][tid]) {
                userOwnedIds[msg.sender].push(tid);
                isIdInList[msg.sender][tid] = true;
            }

            // 報酬の加算
            if (treasureRewards[tid].exists) {
                totalReward += treasureRewards[tid].chhAmount;
            }
        }

        // 5. 送金
        if (totalReward > 0) {
            require(chhToken.transfer(msg.sender, totalReward), "CHH transfer failed");
        }

        emit SessionCompleted(msg.sender, totalReward, treasureIds, block.timestamp);
    }

    /**
     * @dev 費用を支払い、本日のClaim制限を解除する
     */
    function resetClaimCooldown() external {
        require(address(paymentToken) != address(0), "Token not set");
        require(lastClaimDay[msg.sender] == (block.timestamp / 1 days), "Reset not required");
        
        require(paymentToken.transferFrom(msg.sender, address(this), resetFee), "Payment failed");
        
        lastClaimDay[msg.sender] = (block.timestamp / 1 days) - 1;
        emit ClaimCooldownReset(msg.sender, resetFee);
    }

    // --- 表示用（View）関数 ---

    /**
     * @dev ユーザーの図鑑データを一括取得
     */
    function getPlayerInventory(address player) external view returns (uint256[] memory ids, uint256[] memory counts) {
        uint256[] memory ownedIds = userOwnedIds[player];
        uint256[] memory rewardCounts = new uint256[](ownedIds.length);
        
        for (uint256 i = 0; i < ownedIds.length; i++) {
            rewardCounts[i] = userInventory[player][ownedIds[i]];
        }
        return (ownedIds, rewardCounts);
    }

    function canClaimToday(address player) external view returns (bool) {
        return (block.timestamp / 1 days) > lastClaimDay[player];
    }
}