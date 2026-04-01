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
    mapping(address => bool) public isTestUser;
    address public koharuAddress;

    uint256 public constant DEADLINE_APRIL = 1777593599;

    event RewardClaimed(address indexed user, uint256 chhAmount);

    constructor(address _chhTokenAddress) Ownable(msg.sender) {
        chhToken = IERC20(_chhTokenAddress);
    }

    // --- 管理用関数 ---

    function setKoharuAddress(address _koharu) external onlyOwner {
        koharuAddress = _koharu;
    }

    function setTestUsers(address[] calldata users, bool status) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            isTestUser[users[i]] = status;
        }
    }

    // --- 確認用関数 ---

    function getClaimStatus(address _user) external view returns (bool) {
        return hasClaimed[_user];
    }

    function setClaimStatus(address _user, bool _status) external onlyOwner {
        hasClaimed[_user] = _status;
    }

    function checkIsTestUser(address _user) external view returns (bool) {
        return isTestUser[_user];
    }

    /**
    * @dev 属性(Role)ごとの報酬内容を返す
    * 戻り値に名前を付けることで、初期化コードを簡略化し警告を回避します。
    */
    function getRewardsByRole(uint8 roleType) public pure returns (UserAssets memory assets) {
        if (roleType == 0) { // こはるさん
            assets.chhBalance = 100000 * 10**18;
            assets.heroRare = 3;
            assets.equipRare = 9;
            assets.itemPotion = 30;
            assets.itemElixir = 10;
            assets.itemWhetstone = 30;
        } else if (roleType == 1) { // テストユーザー
            assets.chhBalance = 100000 * 10**18;
            assets.heroUncommon = 3;
            assets.equipCommon = 9;
            assets.itemPotion = 30;
            assets.itemElixir = 10;
            assets.itemWhetstone = 30;
        } else if (roleType == 2) { // 新規（4月）
            assets.heroCommon = 3;
            assets.heroUncommon = 1;
            assets.itemPotion = 30;
            assets.itemElixir = 1;
            assets.itemWhetstone = 10;
        } else if (roleType == 3) { // 新規（5月以降）
            assets.heroCommon = 3;
            assets.itemPotion = 10;
            assets.itemElixir = 1;
            assets.itemWhetstone = 5;
        }
        // else の場合は初期値（すべて0）の assets がそのまま返ります
    }

    function previewClaimAmount(address _user) public view returns (UserAssets memory) {
        if (hasClaimed[_user]) {
            return UserAssets(0,0,0,0,0,0,0,0,0,0);
        }

        if (_user == koharuAddress) {
            return getRewardsByRole(0);
        } else if (isTestUser[_user]) {
            return getRewardsByRole(1);
        } else {
            if (block.timestamp <= DEADLINE_APRIL) {
                return getRewardsByRole(2);
            } else {
                return getRewardsByRole(3);
            }
        }
    }

    /**
     * @dev 報酬をClaimし、更新後の全資産状況を返す
     */
    function claim() external returns (UserAssets memory) {
        require(!hasClaimed[msg.sender], "Already claimed");
        
        UserAssets memory reward = previewClaimAmount(msg.sender);
        hasClaimed[msg.sender] = true;

        // ストレージの更新
        UserAssets storage current = userAssets[msg.sender];
        current.chhBalance += reward.chhBalance;
        current.heroCommon += reward.heroCommon;
        current.heroUncommon += reward.heroUncommon;
        current.heroRare += reward.heroRare;
        current.equipCommon += reward.equipCommon;
        current.equipUncommon += reward.equipUncommon;
        current.equipRare += reward.equipRare;
        current.itemPotion += reward.itemPotion;
        current.itemElixir += reward.itemElixir;
        current.itemWhetstone += reward.itemWhetstone;

        if (reward.chhBalance > 0) {
            require(chhToken.balanceOf(address(this)) >= reward.chhBalance, "Insufficient CHH");
            require(chhToken.transfer(msg.sender, reward.chhBalance), "Transfer failed");
        }

        emit RewardClaimed(msg.sender, reward.chhBalance);
        
        return current; // 更新後の資産状況を返す
    }
}