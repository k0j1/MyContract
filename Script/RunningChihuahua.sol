// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract CHHClaimVault {
    using Strings for uint256;

    IERC20 public immutable token;
    address public owner;
    address public signerAddress = 0xB6eDacfc0dFc759E9AC5b9b8B6eB32310ac1Bb49;

    struct ClaimInfo {
        uint32 lastClaimDay;
        uint8 dailyCount;
    }
    mapping(address => ClaimInfo) public userClaims;

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
        owner = 0x9eB566Cc59e3e9D42209Dd2d832740a6A74f5F23;
    }

    // ================= 追加した関数 =================

    /**
     * @dev コントラクト内の現在のトークン残高を確認する (Wei単位)
     */
    function getVaultBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }
    function getVaultBalanceInteger() public view returns (uint256) {
        return token.balanceOf(address(this)) * 10^18;
    }

    // ===============================================

    function claimScore(uint256 score, bytes calldata signature) external {
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, score));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        address recoveredSigner = _recover(ethSignedMessageHash, signature);
        require(recoveredSigner == signerAddress, "Invalid signature");

        // 制限チェック (60,000)
        uint256 maxScore = 60000;
        if (score > maxScore) {
            revert(string(abi.encodePacked("Score limit exceeded. Received: ", score.toString())));
        }

        uint32 currentDay = uint32(block.timestamp / 86400); 
        ClaimInfo storage info = userClaims[msg.sender];
        if (info.lastClaimDay < currentDay) {
            info.lastClaimDay = currentDay;
            info.dailyCount = 1;
        } else {
            require(info.dailyCount < 10, "Daily limit reached");
            info.dailyCount += 1;
        }

        uint256 rewardAmount = (score * 5 * 10^18) / 100 ;
        
        // 送金前の残高チェック (内部的にも実行)
        require(getVaultBalance() >= rewardAmount, "Insufficient vault balance");
        
        require(token.transfer(msg.sender, rewardAmount), "Transfer failed");
    }

    function _recover(bytes32 hash, bytes memory sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s);
    }

    function setSignerAddress(address _newSigner) external {
        require(msg.sender == owner, "Not owner");
        signerAddress = _newSigner;
    }

    function withdrawTokens() external {
        require(msg.sender == owner, "Not owner");
        token.transfer(owner, getVaultBalance());
    }
}