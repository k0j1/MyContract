// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ChihuahuaShop is Ownable {
    // $CHH トークンのコントラクト
    IERC20 public constant CHH_TOKEN = IERC20(0xb0525542E3D818460546332e76E511562dFf9B07);
    
    // 売上金の送付先
    address public constant TREASURY = 0x65F5661319C4d23c973C806e1e006Bb06d5557D2;

    // 署名者アドレス
    address public signerAddress = 0xB6eDacfc0dFc759E9AC5b9b8B6eB32310ac1Bb49;

    // アイテム1個あたりの定価 (200 $CHH)
    uint256 public constant ITEM_UNIT_PRICE = 200 * 10**18;

    event ItemsPurchased(address indexed buyer, uint256 amount, uint256 paidAmount);
    event SignerChanged(address indexed oldSigner, address indexed newSigner);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev 署名者アドレスを変更する（オーナーのみ）
     */
    function setSignerAddress(address _newSigner) external onlyOwner {
        require(_newSigner != address(0), "Invalid address");
        address oldSigner = signerAddress;
        signerAddress = _newSigner;
        emit SignerChanged(oldSigner, _newSigner);
    }

    /**
     * @dev アイテムを購入
     * @param amount 購入個数
     * @param payAmount 支払うトークン量（18桁のwei単位）
     */
    function buyItem(uint256 amount, uint256 payAmount) external {
        require(amount > 0, "Amount must be > 0");

        // 期待される最大金額 (個数 * 200 $CHH)
        uint256 expectedMaxPrice = ITEM_UNIT_PRICE * amount;

        // 【条件】支払金額が (個数 * 200) を超える場合はエラー
        // これにより、まとめ買い割引（500 $CHHなど）は許容されますが、ぼったくり設定は防がれます
        require(payAmount <= expectedMaxPrice, "Payment exceeds expected price");

        // 実際の転送処理
        require(CHH_TOKEN.transferFrom(msg.sender, TREASURY, payAmount), "Transfer failed");

        // 購入イベントの発行
        emit ItemsPurchased(msg.sender, amount, payAmount);
    }
}