// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

abstract contract Ownable {
    address private _owner;
    constructor(address initialOwner) { _owner = initialOwner; }
    function owner() public view virtual returns (address) { return _owner; }
    modifier onlyOwner() { require(owner() == msg.sender, "Ownable: caller is not the owner"); _; }
}

contract QuestTreasury is Ownable {
    mapping(address => bool) public managers;

    // オーナーまたはマネージャーのみ実行可能にするモディファイア
    modifier onlyManager() {
        require(owner() == msg.sender || managers[msg.sender], "QuestTreasury: caller is not a manager");
        _;
    }

    // マネージャーの追加（オーナーのみ）
    function addManager(address manager) external onlyOwner {
        managers[manager] = true;
    }

    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    constructor() Ownable(msg.sender) {}

    // 引き出し関数（マネージャー権限で実行可能）
    function withdraw(address token, address to, uint256 amount) external onlyManager {
        require(IERC20(token).transfer(to, amount), "Transfer failed");
        emit Withdrawn(token, to, amount);
    }

    function withdrawAll(address token, address to) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(IERC20(token).transfer(to, balance), "Transfer failed");
        emit Withdrawn(token, to, balance);
    }

    receive() external payable {}
    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }
}