// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../PrimaryMarket.sol";
import "./ReservePool.sol";
import "../cdp/VaultManager.sol";

contract StakingPool is Ownable {
    uint256 public totalReserveFees;
    
    uint256 public totalIUSDFees;
    
    PrimaryMarket public primaryMarket;
    ReservePool reservePool;
    VaultManager vaultManager;
    
    function setAddresses(
        PrimaryMarket _primaryMarket, 
        ReservePool _reservePool, 
        VaultManager _vaultManager
    ) external onlyOwner {

        primaryMarket = _primaryMarket;
        reservePool = _reservePool;
        vaultManager = _vaultManager;
        renounceOwnership();
    }
    
    function increaseIUSDFees(
        uint256 _amount
    ) external 
    onlyPrimaryMarketContract 
    {
        totalIUSDFees = totalIUSDFees + _amount;
    }
    
    function increaseReserveFees(
        uint256 _amount
    ) external 
        onlyVaultManagerContract 
    {
        totalReserveFees = totalReserveFees + _amount;
    }
    
    modifier onlyPrimaryMarketContract 
    {
        require(
            msg.sender == address(primaryMarket), 
            "StakingPool: Caller is not the Borrowing contract"
        );
        _;
    }
    
    modifier onlyVaultManagerContract 
    {
        require(
            msg.sender == address(vaultManager), 
            "StakingPool: Caller is not the VaultManager contract"
        );
        _;
    }
    
    modifier onlyReservePool {
        require(
            msg.sender == address(reservePool), 
            "StakingPool: Caller is not the ReservePool"
        );
        _;
    }
    
    receive() external payable onlyReservePool {
    }
    
}
