// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../PrimaryMarket.sol";
import "../cdp/VaultManager.sol";
import "./StableCoinPool.sol";

contract ReservePool is Ownable {
    PrimaryMarket public primaryMarket;
    VaultManager public vaultManager;
    StableCoinPool public stableCoinPool;
    
    uint256 internal totalETHDeposited;
    uint256 internal totalIUSDDebt; 
    
    function setAddresses(
        PrimaryMarket _primaryMarket, 
        VaultManager _vaultManagerAddress, 
        StableCoinPool _stableCoinPoolAddress
    ) external onlyOwner {
        primaryMarket = _primaryMarket;
        vaultManager = _vaultManagerAddress;
        stableCoinPool = _stableCoinPoolAddress;
        renounceOwnership();
    }
    
    // Getters
    function getETHDeposited() external view returns (uint) {
        return totalETHDeposited;
    }

    function getIUSDDebt() external view returns (uint) {
        return totalIUSDDebt;
    }
    
    // Main functionality 
    function sendETH(address _account, uint _amount) external onlyPrimaryMarketOrVaultManagerOrStableCoinPool {
        totalETHDeposited = totalETHDeposited - _amount;
        (bool success, ) = _account.call{ value: _amount }("");
        require(success, "ReservePool: sending ETH failed");
    }
    
    function increaseIUSDDebt(uint _amount) external onlyPrimaryMarketOrVaultManager {
        totalIUSDDebt  = totalIUSDDebt + _amount;
    }

    function decreaseIUSDDebt(uint _amount) external onlyPrimaryMarketOrVaultManagerOrStableCoinPool {
        totalIUSDDebt = totalIUSDDebt - _amount;
    }
    
    // Modifiers
    modifier onlyPrimaryMarketContract {
        require(msg.sender == address(primaryMarket), "ReservePool: Caller is not the Borrowing contract");
        _;
    }
    
    modifier onlyPrimaryMarketOrVaultManager {
        require(msg.sender == address(primaryMarket) || msg.sender == address(vaultManager), "ReservePool: Caller is not the Borrowing or VaultManager contract");
        _;
    }
    
    modifier onlyPrimaryMarketOrVaultManagerOrStableCoinPool {
        require(msg.sender == address(primaryMarket) || msg.sender == address(vaultManager) || msg.sender == address(stableCoinPool), "ReservePool: Caller is not the Borrowing or VaultManager or StableCoinPool contract");
        _;
    }
    
    // Fallback
    receive() external payable onlyPrimaryMarketContract {
        totalETHDeposited = totalETHDeposited + msg.value;
    }
}
