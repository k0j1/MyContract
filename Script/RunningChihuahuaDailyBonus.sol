// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";

contract DailyBonus {
    using Strings for uint256;

    address public owner;
    address public signerAddress = 0xB6eDacfc0dFc759E9AC5b9b8B6eB32310ac1Bb49;

    mapping(address => uint256) public lastClaimTime;

    constructor() {
        owner = 0x9eB566Cc59e3e9D42209Dd2d832740a6A74f5F23;
    }

    // 日本時間 9:00 = UTC 0:00 なので、Unixタイムスタンプを86400秒(1日)で割るだけで判定可能
    function canClaim(address user) public view returns (bool) {
        if (lastClaimTime[user] == 0) return true;
        
        // JST 9:00のリセットは UTC 0:00のリセットと同じ
        // 現在の日(UTC)と前回のClaim日(UTC)を比較
        return (block.timestamp / 1 days) > (lastClaimTime[user] / 1 days);
    }

    function claim() public {
        require(canClaim(msg.sender), "Next claim available at JST 9:00 AM");
        
        lastClaimTime[msg.sender] = block.timestamp;
        
        // ここでイベントを発行（バックエンドがこれを検知してDB更新する）
        emit BonusClaimed(msg.sender, block.timestamp);
    }

    event BonusClaimed(address indexed user, uint256 timestamp);
}
