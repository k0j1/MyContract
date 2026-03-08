// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GachaPayment
 * @dev Handles CHH token payments for Hero and Equipment Gacha pulls.
 */
contract GachaPayment is Ownable {
    IERC20 public chhToken;
    address public treasury;

    // Pull types
    string public constant TYPE_HERO_SINGLE = "HERO_SINGLE";
    string public constant TYPE_HERO_TRIPLE = "HERO_TRIPLE";
    string public constant TYPE_EQUIP_SINGLE = "EQUIP_SINGLE";
    string public constant TYPE_EQUIP_TRIPLE = "EQUIP_TRIPLE";

    event GachaPaid(
        address indexed user,
        string gachaType,
        uint256 amount,
        uint256 timestamp
    );

    constructor(address _chhToken, address _treasury) Ownable(msg.sender) {
        chhToken = IERC20(_chhToken);
        treasury = _treasury;
    }

    /**
     * @dev Pay for a gacha pull.
     * @param gachaType The type of gacha (e.g., "HERO_SINGLE")
     * @param amount The amount of CHH tokens to pay
     */
    function payForGacha(string memory gachaType, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(
            chhToken.transferFrom(msg.sender, treasury, amount),
            "Transfer failed"
        );
        
        emit GachaPaid(msg.sender, gachaType, amount, block.timestamp);
    }

    /**
     * @dev Update the treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
    }

    /**
     * @dev Update the CHH token address.
     */
    function setToken(address _chhToken) external onlyOwner {
        require(_chhToken != address(0), "Invalid address");
        chhToken = IERC20(_chhToken);
    }
}
