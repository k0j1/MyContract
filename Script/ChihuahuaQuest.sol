// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title ChihuahuaQuest
 * @dev 報酬受取、クールダウンリセット、オンチェーン図鑑、不正防止バリデーションを統合
 */
contract ChihuahuaQuest is Ownable {
    using ECDSA for bytes32;

    // --- 設定変数 ---
    IERC20 public immutable chhToken;       // 報酬用CHHトークン
    IERC20 public paymentToken;             // リセット用トークン (USDC等)
    address public backendSigner;           // 署名検証用アドレス
    uint256 public resetFee;                // リセット費用

    // --- 報酬・図鑑データ構造 ---
    struct RewardConfig {
        uint256 chhAmount;
        bool exists;
    }

    mapping(uint256 => RewardConfig) public treasureRewards;    // お宝報酬設定
    mapping(address => uint256) public lastClaimDay;            // 最終受取日 (JST 9:00基準)
    mapping(address => uint256) public nonces;                  // リプレイ攻撃防止

    // 図鑑ストレージ
    mapping(address => mapping(uint256 => uint256)) public userInventory;   // player => tid => count
    mapping(address => uint256[]) private userOwnedIds;                     // playerの所持IDリスト
    mapping(address => mapping(uint256 => bool)) private isIdInList;        // 重複登録防止用フラグ

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

    // --- 管理者用関数 (Owner Only) ---

    /**
     * @dev 報酬設定をバッチ更新 (chhAmountsInEther は 10^18 倍前の値を入力)
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
     * @dev 支払い設定の更新
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
     * @dev プールされているCHHを回収
     */
    function withdrawCHHTokens() external onlyOwner {
        uint256 balance = chhToken.balanceOf(address(this));
        require(balance > 0, "No balance");
        require(chhToken.transfer(owner(), balance), "Transfer failed");
    }

    /**
     * @dev 回収された支払いトークン(USDC等)を回収
     */
    function withdrawPaymentTokens() external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        if (balance > 0) paymentToken.transfer(owner(), balance);
    }

    /**
     * @dev 誤送信トークンの救出用
     */
    function recoverERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(owner(), amount);
    }

    // --- メインロジック ---

    /**
     * @dev ゲーム結果を記録し報酬を配布。不正バリデーション付き。
     */
    function recordGameSession(
        uint256[] calldata treasureIds,
        uint256 nonce,
        bytes calldata signature
    ) external {
        // 1. 入力バリデーション
        require(treasureIds.length > 0 && treasureIds.length <= 10, "Invalid IDs length (1-10)");
        
        // 重複チェック (二重ループ: 要素数10以下ならこれが最安)
        for (uint256 i = 0; i < treasureIds.length; i++) {
            for (uint256 j = i + 1; j < treasureIds.length; j++) {
                require(treasureIds[i] != treasureIds[j], "Duplicate IDs detected");
            }
        }

        // 2. 日付と署名の検証
        uint256 currentDay = block.timestamp / 1 days;
        require(currentDay > lastClaimDay[msg.sender], "Already claimed today");
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
            
            userInventory[msg.sender][tid] += 1;
            if (!isIdInList[msg.sender][tid]) {
                userOwnedIds[msg.sender].push(tid);
                isIdInList[msg.sender][tid] = true;
            }

            if (treasureRewards[tid].exists) {
                totalReward += treasureRewards[tid].chhAmount;
            }
        }

        // 5. 報酬送金
        if (totalReward > 0) {
            require(chhToken.transfer(msg.sender, totalReward), "CHH transfer failed");
        }

        emit SessionCompleted(msg.sender, totalReward, treasureIds, block.timestamp);
    }

    /**
     * @dev 手数料を支払い、本日の制限をリセット
     */
    function resetClaimCooldown() external {
        require(address(paymentToken) != address(0), "Payment token not set");
        require(lastClaimDay[msg.sender] == (block.timestamp / 1 days), "No reset needed");
        
        require(paymentToken.transferFrom(msg.sender, address(this), resetFee), "Payment failed");
        
        lastClaimDay[msg.sender] = (block.timestamp / 1 days) - 1;
        emit ClaimCooldownReset(msg.sender, resetFee);
    }

    // --- View関数 ---

    /**
     * @dev ユーザーの図鑑（IDリストと各個数）を一括取得
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