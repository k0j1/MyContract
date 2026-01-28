// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ReversiClaim is Ownable {
    using ECDSA for bytes32;

    // $CHH Token Address
    IERC20 public immutable chhToken;
    
    // Server-side signer address (Hardcoded)
    address public constant signerAddress = 0xB6eDacfc0dFc759E9AC5b9b8B6eB32310ac1Bb49;
    
    // Daily Limit: User Address => Last Claim Timestamp
    mapping(address => uint256) public lastClaimTime;

    event Claimed(address indexed user, uint256 amount);

    // Initial setup
    constructor() Ownable(msg.sender) {
        // Target Token Contract
        chhToken = IERC20(0xb0525542E3D818460546332e76E511562dFf9B07);
        
        // Transfer ownership to the specified wallet immediately
        _transferOwnership(0x9eB566Cc59e3e9D42209Dd2d832740a6A74f5F23);
    }

    // Check if user can claim today (returns true if eligible)
    function checkDailyLimit(address user) public view returns (bool) {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 lastClaimedDay = lastClaimTime[user] / 1 days;
        
        // Return true if current day is greater than last claimed day
        return currentDay > lastClaimedDay;
    }

    // Claim function
    function claim(uint256 amount, bytes calldata signature) external {
        require(amount > 0, "Amount must be > 0");
        // Limit check for RAW amount (e.g. 1500 tokens, not wei)
        require(amount <= 1500, "Amount exceeds limit (1500 CHH)");

        // 1. Check Daily Limit
        require(checkDailyLimit(msg.sender), "Already claimed today (resets at UTC 0:00)");

        // 2. Verify Signature
        // Backend signs: keccak256(abi.encodePacked(address, amount))
        // NOTE: removed address(this) to match PHP backend
        bytes32 hash = keccak256(abi.encodePacked(msg.sender, amount));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(hash);
        
        address recoveredSigner = ethSignedMessageHash.recover(signature);
        require(recoveredSigner == signerAddress, "Invalid signature");

        // 3. Update timestamp
        lastClaimTime[msg.sender] = block.timestamp;

        // 4. Transfer Tokens
        // Convert raw amount to Wei (assuming 18 decimals)
        uint256 amountWei = amount * 10**18;

        require(chhToken.balanceOf(address(this)) >= amountWei, "Contract has insufficient balance");
        bool success = chhToken.transfer(msg.sender, amountWei);
        require(success, "Token transfer failed");
        
        emit Claimed(msg.sender, amountWei);
    }

    // Check remaining contract balance
    function getRemainingBalance() external view returns (uint256) {
        return chhToken.balanceOf(address(this));
    }

    // Withdraw function for the owner
    function withdrawToken(uint256 amount) external onlyOwner {
        require(chhToken.transfer(msg.sender, amount), "Transfer failed");
    }
}