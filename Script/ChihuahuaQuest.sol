// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title ChihuahuaQuest
 * @dev 1日1回、財宝報酬を一括受取するための最適化済みコントラクト
 * 履歴はイベントログから取得し、コントラクト側はリセット判定のみを管理することでガス代を節約します。
 */
contract ChihuahuaQuest is Ownable {
    using ECDSA for bytes32;

    IERC20 public immutable chhToken;
    address public backendSigner;

    struct RewardConfig {
        uint256 chhAmount;
        bool exists;
    }

    // 財宝設定
    mapping(uint256 => RewardConfig) public treasureRewards;
    
    // ユーザーの最終報酬受取日 (block.timestamp / 1 days)
    // 日本時間 9:00 (UTC 0:00) に自動的に日付が切り替わります
    mapping(address => uint256) public lastClaimDay;

    // リプレイ攻撃防止用
    mapping(address => uint256) public nonces;

    // --- Events ---
    // 財宝の獲得履歴はすべてこのログからJavaScript（オンチェーン外）で集計します
    event SessionCompleted(
        address indexed player, 
        uint256 totalReward, 
        uint256[] treasureIds, 
        uint256 timestamp
    );
    event RewardConfigUpdated(uint256 indexed treasureId, uint256 chhAmount);

    constructor(address _chhTokenAddress, address _backendSigner) Ownable(msg.sender) {
        require(_chhTokenAddress != address(0), "Invalid token address");
        chhToken = IERC20(_chhTokenAddress);
        backendSigner = _backendSigner;
    }

    /**
     * @dev 財宝の報酬設定を追加・更新する（一括対応）
     */
    function setTreasureRewards(uint256[] calldata treasureIds, uint256[] calldata chhAmounts) external onlyOwner {
        require(treasureIds.length == chhAmounts.length, "Mismatched input lengths");
        for (uint256 i = 0; i < treasureIds.length; i++) {
            treasureRewards[treasureIds[i]] = RewardConfig(chhAmounts[i], true);
            emit RewardConfigUpdated(treasureIds[i], chhAmounts[i]);
        }
    }

    /**
     * @dev 署名者アドレスの変更
     */
    function setBackendSigner(address _newSigner) external onlyOwner {
        require(_newSigner != address(0), "Invalid signer address");
        backendSigner = _newSigner;
    }

    /**
     * @dev ゲームセッションを記録し、1日分の報酬を一括で受け取る
     * @param treasureIds 獲得した財宝の配列
     * @param nonce 現在のユーザーのnonce
     * @param signature バックエンドからの署名
     */
    function recordGameSession(
        uint256[] calldata treasureIds,
        uint256 nonce,
        bytes calldata signature
    ) external {
        // 1. 日付チェック (JST 9:00 = UTC 0:00 リセット)
        uint256 currentDay = block.timestamp / 1 days;
        require(currentDay > lastClaimDay[msg.sender], "Already claimed today (Next reset: JST 9:00)");

        // 2. Nonceの検証
        require(nonce == nonces[msg.sender], "Invalid nonce");

        // 3. 署名の検証
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, treasureIds, nonce, address(this)));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(ethSignedMessageHash, signature);
        require(recoveredSigner == backendSigner, "Invalid signature");

        // 4. 状態の更新
        nonces[msg.sender]++;
        lastClaimDay[msg.sender] = currentDay;

        // 5. 報酬の計算
        uint256 totalReward = 0;
        for (uint256 i = 0; i < treasureIds.length; i++) {
            uint256 tid = treasureIds[i];
            if (treasureRewards[tid].exists) {
                totalReward += treasureRewards[tid].chhAmount;
            }
        }

        // 6. CHHトークンの転送
        if (totalReward > 0) {
            require(chhToken.transfer(msg.sender, totalReward), "Token transfer failed");
        }

        // 7. イベントログの出力 (これが履歴データになる)
        emit SessionCompleted(msg.sender, totalReward, treasureIds, block.timestamp);
    }

    /**
     * @dev フロントエンド用：今日報酬を受け取れる状態か確認
     */
    function canClaimToday(address player) external view returns (bool) {
        return (block.timestamp / 1 days) > lastClaimDay[player];
    }
}