// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MiningQuestReward
 * @dev サーバー署名検証、報酬範囲チェック、ユーザー累計額管理を含む報酬請求コントラクト
 */
contract MiningQuestReward is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    // クエスト設定構造体
    struct QuestConfig {
        uint256 minReward;
        uint256 maxReward;
        bool exists;
    }

    // $CHH トークン設定
    IERC20 public immutable rewardToken;
    
    // サーバー側の署名用アドレス
    address public constant signerAddress = 0xB6eDacfc0dFc759E9AC5b9b8B6eB32310ac1Bb49;
    
    // quest_id (種類) => 報酬範囲の設定
    mapping(uint256 => QuestConfig) public questConfigs;
    
    // fid => questPid (ユニークID) => 請求済みフラグ
    mapping(uint256 => mapping(uint256 => bool)) public claimedQuests;
    
    // fid => 累計請求済み額
    mapping(uint256 => uint256) public totalClaimedPerUser;

    event RewardClaimed(
        uint256 indexed fid, 
        uint256 indexed questPid, 
        uint256 questId
    );

    constructor() Ownable(msg.sender) {
        // トークンアドレスの設定
        rewardToken = IERC20(0xb0525542E3D818460546332e76E511562dFf9B07);
        
        // 指定された管理者アドレスへ所有権を移譲
        _transferOwnership(0x9eB566Cc59e3e9D42209Dd2d832740a6A74f5F23);

        // クエスト報酬範囲の初期定義
        _setQuestConfig(1, 2, 200);     // id=1 : 2-200
        _setQuestConfig(2, 5, 500);     // id=2 : 5-500
        _setQuestConfig(3, 10, 1200);   // id=3 : 10-1200
        _setQuestConfig(4, 30, 3000);   // id=4 : 30-3000
        _setQuestConfig(5, 80, 8000);   // id=5 : 80-8000
    }

    // 内部用：報酬範囲設定
    function _setQuestConfig(uint256 id, uint256 min, uint256 max) internal {
        questConfigs[id] = QuestConfig(min, max, true);
    }

    // オーナー用：報酬範囲の更新・追加
    function updateQuestConfig(uint256 id, uint256 min, uint256 max) external onlyOwner {
        _setQuestConfig(id, min, max);
    }

    /**
     * @notice 報酬請求メイン関数
     * @param fid ユーザーFID
     * @param questPid DB上のユニークなクエストID (quest_miningテーブル等のid)
     * @param questId クエストの種類 (1-5等)
     * @param questReward クエスト報酬額 (Raw単位)
     * @param reward 今回の請求額 (Raw単位)
     * @param totalReward ユーザーの累計報酬可能額 (quest_player_statsのtotal_reward)
     * @param signature サーバー側で生成された署名
     */
    function claimReward(
        uint256 fid,
        uint256 questPid,
        uint256 questId,
        uint256 questReward,
        uint256 reward,
        uint256 totalReward,
        bytes calldata signature
    ) external nonReentrant {
        // --- 1. 二重請求チェック ---
        require(!claimedQuests[fid][questPid], "Quest PID already claimed by this FID");

        // --- 2. クエスト設定と範囲チェック ---
        QuestConfig memory config = questConfigs[questId];
        require(config.exists, "Invalid Quest ID");
        require(questReward >= config.minReward, "Amount below min_reward");
        require(questReward <= config.maxReward, "Amount exceeds max_reward");

        // --- 3. 累計額と統計情報のチェック ---
        // (既に請求した額 + 今回の額) が統計上限を超えていないか
        require(totalClaimedPerUser[fid] + reward <= totalReward, "Cumulative reward exceeds total_reward limit");

        // --- 4. 署名検証 ---
        // 全てのパラメータとコントラクトアドレスをハッシュ化
        bytes32 messageHash = keccak256(abi.encodePacked(
            fid,
            questPid,
            questId,
            questReward,
            reward,
            totalReward,
            address(this)
        ));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        
        address recoveredSigner = ethSignedMessageHash.recover(signature);
        require(recoveredSigner == signerAddress, "Invalid server signature");

        // --- 5. 状態更新 ---
        claimedQuests[fid][questPid] = true;
        totalClaimedPerUser[fid] += reward;

        // --- 6. トークン送金 (18 Decimals) ---
        uint256 amountWei = reward * 10**18;
        require(rewardToken.balanceOf(address(this)) >= amountWei, "Contract balance insufficient");
        
        bool success = rewardToken.transfer(msg.sender, amountWei);
        require(success, "Token transfer failed");

        emit RewardClaimed(fid, questPid, questId);
    }

    // 残高確認用
    function getRemainingBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    // オーナー用：トークン回収
    function withdrawToken(uint256 amount) external onlyOwner {
        require(rewardToken.transfer(msg.sender, amount), "Withdraw failed");
    }
}