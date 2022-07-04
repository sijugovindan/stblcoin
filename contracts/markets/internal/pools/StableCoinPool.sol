// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../tokens/stablecoins/IdeaUSD.sol";
import "../cdp/VaultManager.sol";

contract StableCoinPool is Ownable {
    IdeaUSD public iusdToken;
    VaultManager public vaultManager;
    
    uint256 internal totalReserveDeposited;
    uint256 internal totalIUSDDeposits;
     
    mapping (address => uint256) public deposits;  // depositor address -> total deposits
     
    function setAddresses(
        IdeaUSD _iusdToken, 
        VaultManager _vaultManager
    ) 
    external 
    onlyOwner 
    {
        iusdToken = _iusdToken;
        vaultManager = _vaultManager;
        
        renounceOwnership();
    }
    
    function deposit(
        uint256 _amount
    ) external 
    {
        deposits[msg.sender] = deposits[msg.sender] + _amount;

        // update IUSD Deposits
        uint256 newTotalIUSDDeposits = totalIUSDDeposits + _amount;
        totalIUSDDeposits = newTotalIUSDDeposits;
        
        // transfer IUSD
        iusdToken.transferFrom(msg.sender, address(this), _amount);
    }
    
    function offset(
        uint256 _IUSDAmount
    ) 
    external 
    onlyVaultManager 
    {
        // decrease debt in active pool 
        totalIUSDDeposits = totalIUSDDeposits - _IUSDAmount;
        
        // burn lusd 
        iusdToken.burn(address(this), _IUSDAmount);
    }
    
    // Getters
    function getReserveDeposited() 
    external 
    view 
    returns (uint) 
    {
        return totalReserveDeposited;
    }
    
    function getTotalIUSDDeposits() 
    external 
    view 
    returns(uint256)
    {
        return totalIUSDDeposits;
    }
    
    modifier onlyVaultManager 
    {
        require(
            msg.sender == address(vaultManager), 
            "StableCoinPool: Sender is not VaultManager"
        );
        _;
    }
    
    // Fallback
    receive() 
    external 
    payable 
    onlyVaultManager 
    {
        totalReserveDeposited = totalReserveDeposited + msg.value;
    }
}
