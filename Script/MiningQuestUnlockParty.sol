// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UnlockParty is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public chhToken;
    address public treasury;
    uint256 public price = 100000 * 10**18;

    // ユーザーアドレス => (パーティID => 解放済みか)
    mapping(address => mapping(uint256 => bool)) public hasUnlocked;

    // イベントにpartyIdを追加
    event unlockPurchased(address indexed buyer, uint256 indexed partyId);
    event PricesUpdated(uint256 price);
    event TreasuryUpdated(address newTreasury);

    constructor(address _chhToken, address _treasury) Ownable(msg.sender) {
        require(_chhToken != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        chhToken = IERC20(_chhToken);
        treasury = _treasury;
    }

    /**
     * @dev パーティ解放する関数
     * @param partyId 解放したいパーティの番号 (2 または 3 のみ許可)
     */
    function unlockParty(uint256 partyId) external nonReentrant {
        // 1. パーティIDのバリデーション (2か3以外はエラー)
        require(partyId == 2 || partyId == 3, "Invalid party ID: Only 2 or 3 allowed");

        // 2. すでにそのパーティを解放していないかチェック
        require(!hasUnlocked[msg.sender][partyId], "This party is already unlocked");

        // 3. 状態の更新（再入攻撃対策のため送金前に実行）
        hasUnlocked[msg.sender][partyId] = true;

        // 4. トークンの転送
        chhToken.safeTransferFrom(msg.sender, treasury, price);

        // 5. イベント発火
        emit unlockPurchased(msg.sender, partyId);
    }

    /**
     * @dev 特定のユーザーが特定のパーティを解放済みか確認するView関数
     */
    function isPartyUnlocked(address user, uint256 partyId) external view returns (bool) {
        return hasUnlocked[user][partyId];
    }

    // --- 管理用関数 (setPrices, setTreasury) は変更なし ---
    function setPrices(uint256 _price) external onlyOwner {
        price = _price;
        emit PricesUpdated(_price);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }
}