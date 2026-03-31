// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardManager is Ownable {

    struct UserAssets {
        uint256 chhBalance;
        uint256 heroCommon;
        uint256 heroUncommon;
        uint256 heroRare;
        uint256 equipCommon;
        uint256 equipUncommon;
        uint256 equipRare;
        uint256 itemPotion;
        uint256 itemElixir;
        uint256 itemWhetstone;
    }

    IERC20 public chhToken;
    
    mapping(address => UserAssets) public userAssets;
    mapping(address => bool) public hasClaimed;
    
    // テストユーザーを判定するためのマッピング
    mapping(address => bool) public isTestUser;
    // こはるさんアドレス
    address public koharuAddress;

    uint256 public constant DEADLINE_APRIL = 1777593599;

    event TestUserStatusUpdated(address indexed user, bool status);
    event KoharuAddressUpdated(address indexed newAddress);

    constructor(address _chhTokenAddress) Ownable(msg.sender) {
        chhToken = IERC20(_chhTokenAddress);
    }

    /**
     * @dev こはるさんのアドレスを設定
     */
    function setKoharuAddress(address _koharu) external onlyOwner {
        koharuAddress = _koharu;
        emit KoharuAddressUpdated(_koharu);
    }

    /**
     * @dev テストユーザーを一人ずつ、または一括で追加・削除する
     * @param users アドレスの配列
     * @param status trueで追加、falseで削除
     */
    function setTestUsers(address[] calldata users, bool status) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            isTestUser[users[i]] = status;
            emit TestUserStatusUpdated(users[i], status);
        }
    }

    function claim() external {
        require(!hasClaimed[msg.sender], "Already claimed");
        hasClaimed[msg.sender] = true;

        UserAssets storage assets = userAssets[msg.sender];
        uint256 rewardChh = 0;

        // 1. こはるさん判定
        if (msg.sender == koharuAddress) {
            rewardChh = 100000 * 10**18;
            assets.chhBalance += rewardChh;
            assets.heroRare += 3;
            assets.equipRare += 9;
            assets.itemPotion += 30;
            assets.itemElixir += 10;
            assets.itemWhetstone += 30;
        } 
        // 2. テストユーザー判定 (mappingにより複数人対応)
        else if (isTestUser[msg.sender]) {
            rewardChh = 100000 * 10**18;
            assets.chhBalance += rewardChh;
            assets.heroUncommon += 3;
            assets.equipCommon += 9;
            assets.itemPotion += 30;
            assets.itemElixir += 10;
            assets.itemWhetstone += 30;
        } 
        // 3. 一般新規ユーザー判定
        else {
            if (block.timestamp <= DEADLINE_APRIL) {
                assets.heroCommon += 3;
                assets.heroUncommon += 1;
                assets.itemPotion += 30;
                assets.itemElixir += 1;
                assets.itemWhetstone += 10;
            } else {
                assets.heroCommon += 3;
                assets.itemPotion += 10;
                assets.itemElixir += 1;
                assets.itemWhetstone += 5;
            }
        }

        if (rewardChh > 0) {
            require(chhToken.balanceOf(address(this)) >= rewardChh, "Insufficient CHH");
            require(chhToken.transfer(msg.sender, rewardChh), "Transfer failed");
        }
    }

    function getUserAssets(address _user) external view returns (UserAssets memory) {
        return userAssets[_user];
    }
}