// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ItemShop
 * @dev ERC20トークン($CHH)を使用してゲーム内アイテムを購入するためのコントラクト
 */
contract ItemShop is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // 決済に使用するERC20トークン ($CHH)
    IERC20 public chhToken;
    
    // 売上が送られる運営のアドレス
    address public treasury;

    // アイテムの価格 (18 decimalsを想定)
    uint256 public potionPrice = 100 * 10**18;    // 100 $CHH
    uint256 public elixirPrice = 500 * 10**18;    // 500 $CHH
    uint256 public whetstonePrice = 100 * 10**18; // 100 $CHH (potionPriceと同じ)

    // イベント定義
    event ItemsPurchased(
        address indexed buyer,
        uint256 potionAmount,
        uint256 elixirAmount,
        uint256 whetstoneAmount, // 追加
        uint256 totalCost
    );
    event PricesUpdated(uint256 newPotionPrice, uint256 newElixirPrice, uint256 newWhetstonePrice);
    event TreasuryUpdated(address newTreasury);

    constructor(address _chhToken, address _treasury) Ownable(msg.sender) {
        require(_chhToken != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        chhToken = IERC20(_chhToken);
        treasury = _treasury;
    }

    /**
     * @dev アイテムを購入する関数
     * @param potionAmount 購入するポーションの数
     * @param elixirAmount 購入するエリクサーの数
     * @param whetstoneAmount 購入する砥石の数 (追加)
     */
    function buyItems(uint256 potionAmount, uint256 elixirAmount, uint256 whetstoneAmount) external nonReentrant {
        require(potionAmount > 0 || elixirAmount > 0 || whetstoneAmount > 0, "Must buy at least one item");

        // 合計コストの計算
        uint256 totalCost = (potionAmount * potionPrice) + 
                            (elixirAmount * elixirPrice) + 
                            (whetstoneAmount * whetstonePrice);

        // ユーザーからトレジャリーへトークンを転送
        chhToken.safeTransferFrom(msg.sender, treasury, totalCost);

        // 購入イベントの発火
        emit ItemsPurchased(msg.sender, potionAmount, elixirAmount, whetstoneAmount, totalCost);
    }

    /**
     * @dev アイテムの価格を更新する関数
     */
    function setPrices(uint256 _potionPrice, uint256 _elixirPrice, uint256 _whetstonePrice) external onlyOwner {
        potionPrice = _potionPrice;
        elixirPrice = _elixirPrice;
        whetstonePrice = _whetstonePrice;
        emit PricesUpdated(_potionPrice, _elixirPrice, _whetstonePrice);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }
}