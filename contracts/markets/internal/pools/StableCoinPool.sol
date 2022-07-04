// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../tokens/stablecoins/IdeaUSD.sol";
import "../cdp/VaultManager.sol";

contract StableCoinPool is Ownable {
    IdeaUSD public iusdToken;
    VaultManager public vaultManager;
    
    uint256 internal totalETHDeposited;
    uint256 internal totalLUSDDeposits;
     
    mapping (address => uint256) public deposits;  // depositor address -> total deposits
     
    function setAddresses(IdeaUSD _iusdToken, VaultManager _vaultManager) external onlyOwner {
        iusdToken = _iusdToken;
        vaultManager = _vaultManager;
        
        renounceOwnership();
    }
    
    function deposit(uint256 _amount) external {
        deposits[msg.sender] = deposits[msg.sender] + _amount;

        // update LUSD Deposits
        uint256 newTotalLUSDDeposits = totalLUSDDeposits + _amount;
        totalLUSDDeposits = newTotalLUSDDeposits;
        
        // transfer LUSD
        iusdToken.transferFrom(msg.sender, address(this), _amount);
    }
    
    function offset(uint256 _IUSDAmount) external onlyVaultManager {
        // decrease debt in active pool 
        totalLUSDDeposits = totalLUSDDeposits - _IUSDAmount;
        
        // burn lusd 
        iusdToken.burn(address(this), _IUSDAmount);
    }
    
    // Getters
    function getETHDeposited() external view returns (uint) {
        return totalETHDeposited;
    }
    
    function getTotalLUSDDeposits() external view returns(uint256){
        return totalLUSDDeposits;
    }
    
    modifier onlyVaultManager {
        require(msg.sender == address(vaultManager), "StableCoinPool: Sender is not VaultManager");
        _;
    }
    
    // Fallback
    receive() external payable onlyVaultManager {
        totalETHDeposited = totalETHDeposited + msg.value;
    }
}
