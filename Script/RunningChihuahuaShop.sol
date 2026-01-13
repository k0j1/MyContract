// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title ItemShop
 * @dev バックエンドの署名を使用してアイテムを販売するコントラクト
 */
contract ItemShop is Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    IERC20 public chhToken;
    address public backendSigner; // PHPバックエンドの公開アドレス
    
    event ItemPurchased(address indexed user, uint256 amount, uint256 payAmount);

    constructor(address _chhToken, address _backendSigner) Ownable(msg.sender) {
        chhToken = IERC20(_chhToken);
        backendSigner = _backendSigner;
    }

    /**
     * @dev 署名者を設定（オーナーのみ）
     */
    function setBackendSigner(address _newSigner) external onlyOwner {
        backendSigner = _newSigner;
    }

    /**
     * @dev アイテムを購入する
     * @param amount 購入するアイテム数
     * @param payAmount 支払額 (wei)
     * @param signature PHPバックエンドで生成された署名
     */
    function buyItem(uint256 amount, uint256 payAmount, bytes calldata signature) external {
        // 1. 署名対象のハッシュを生成
        // scoreService と同様に、送信者・個数・金額をパックしてハッシュ化
        bytes32 hash = keccak256(abi.encodePacked(msg.sender, amount, payAmount));
        
        // 2. Ethereumの署名フォーマットに変換
        bytes32 ethSignedMessageHash = hash.toEthSignedMessageHash();
        
        // 3. 署名からアドレスを復元
        address recoveredSigner = ethSignedMessageHash.recover(signature);
        
        // 4. 署名者が正しいかチェック
        require(recoveredSigner == backendSigner, "Invalid signature: Security check failed");

        // 5. トークンの支払い
        require(chhToken.balanceOf(msg.sender) >= payAmount, "Insufficient CHH balance");
        require(chhToken.allowance(msg.sender, address(this)) >= payAmount, "Token not approved");

        bool success = chhToken.transferFrom(msg.sender, address(this), payAmount);
        require(success, "Token transfer failed");

        emit ItemPurchased(msg.sender, amount, payAmount);
    }

    /**
     * @dev 売り上げトークンを回収（オーナーのみ）
     */
    function withdrawTokens(address to) external onlyOwner {
        uint256 balance = chhToken.balanceOf(address(this));
        chhToken.transfer(to, balance);
    }
}