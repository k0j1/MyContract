// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor(address initialOwner) { _owner = initialOwner; }
    function owner() public view virtual returns (address) { return _owner; }
    modifier onlyOwner() { require(owner() == msg.sender, "Ownable: caller is not the owner"); _; }
}

contract QuestManager is Ownable {
    IERC20 public chhToken;
    address public treasury;
    event QuestDeparted(address indexed player, uint256 questRank, uint256 cost);

    constructor(address _chhToken, address _treasury) Ownable(msg.sender) {
        chhToken = IERC20(_chhToken);
        treasury = _treasury;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function departQuest(uint256 questRank, uint256 cost) external {
        // 費用がある場合のみトークンを転送
        if (cost > 0) {
            require(chhToken.transferFrom(msg.sender, treasury, cost), "CHH transfer failed");
        }
        emit QuestDeparted(msg.sender, questRank, cost);
    }
}