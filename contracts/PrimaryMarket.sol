// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./helpers/Base.sol";
import "./markets/external/price/PriceFeed.sol";
import "./markets/internal/cdp/VaultManager.sol";
import "./tokens/stablecoins/IdeaUSD.sol";

// pools 
import "./markets/internal/pools/ReservePool.sol";
import "./markets/internal/pools/StableCoinPool.sol";
import "./markets/internal/pools/GasPool.sol";
import "./markets/internal/pools/StakingPool.sol";

//import "hardhat/console.sol";

contract PrimaryMarket is Base, Ownable{
    PriceFeed public priceFeed;
    VaultManager public vaultManager;
    IdeaUSD public iusdToken;
    
    // pools 
    ReservePool public reservePool;
    StableCoinPool public stableCoinPool;
    GasPool public gasPool;
    StakingPool public stakingPool;
    
    constructor(){
        
        priceFeed = new PriceFeed();
        priceFeed.setPrice(1000 * 10**18);
        
        // pools 
        reservePool = new ReservePool();
        stableCoinPool = new StableCoinPool();
        gasPool = new GasPool();
        stakingPool = new StakingPool();
        
        // initialize vault manager
        vaultManager = new VaultManager();
        
        // iusdToken
        iusdToken = new IdeaUSD(address(vaultManager), address(stableCoinPool));

        // set addresses
        reservePool.setAddresses(this, vaultManager, stableCoinPool);
        stableCoinPool.setAddresses(iusdToken, vaultManager);
        stakingPool.setAddresses(this, reservePool, vaultManager);
        vaultManager.setAddresses(priceFeed, iusdToken, stableCoinPool, gasPool, stakingPool, reservePool);
    }
    
    function mint(uint256 _IUSDAmount) public payable {
       _borrow(_IUSDAmount);
    }
    
    function repay() external {
        _repay();
       
    }

    function redeem() external {
       
    }

    function _borrow(uint256 _IUSDAmount) internal {
        uint256 IUSDAmount = _IUSDAmount * DECIMAL_PRECISION;
        uint256 debt = IUSDAmount;
        
        // get price 
        uint256 price = priceFeed.getPrice();
        console.log("Price %s", price);
        
        // calculations
        uint256 collateralRatio = msg.value * price / debt;
        console.log("collateralRatio %s", collateralRatio);
        
        // validate collateral ratio 
        _requireCollateralRatioIsAboveMCR(collateralRatio);
        
        vaultManager.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        console.log("After decay base rate");
        
        uint256 borrowingFee = vaultManager.getBorrowingFee(IUSDAmount);
        console.log("borrowingFee %s", borrowingFee);
        
        // increase fees in staking pool 
        stakingPool.increaseIUSDFees(borrowingFee);

        // mint IUSD for StakingPool
        iusdToken.mint(address(stakingPool), borrowingFee);
        
        uint256 compositeDebt = debt + IUSD_GAS_COMPENSATION + borrowingFee;
        console.log("compositeDebt %s", compositeDebt);
        
        // create vault 
        vaultManager.createVault(msg.sender, msg.value, compositeDebt, 1);
        
        // send Eth to ReservePool
        _addCollateralToReservePool(msg.value);
        console.log("ReservePool Collateral Deposited %s", reservePool.getETHDeposited());
        
        // mint tokens for user
        iusdToken.mint(msg.sender, IUSDAmount);
        console.log("Balance of borrower %s", iusdToken.balanceOf(msg.sender));
        
        // mint tokens for gas compensations
        iusdToken.mint(address(gasPool), IUSD_GAS_COMPENSATION);
        console.log("gas compensations %s", iusdToken.balanceOf(address(gasPool)));
        
        // increase IUSD Debt 
        reservePool.increaseIUSDDebt(compositeDebt);
        console.log("ReservePool IUSD Debt %s", reservePool.getIUSDDebt());
    }
    
    function _repay() internal {
        uint256 collateral = vaultManager.getVaultCollateral(msg.sender);
        uint256 debt = vaultManager.getVaultDebt(msg.sender);
        
        uint256 debtRepayment = debt - IUSD_GAS_COMPENSATION;
        require(iusdToken.balanceOf(msg.sender) >= debtRepayment, "Borrower doesnt have enough IUSD to make repayment");

        vaultManager.closeVault(msg.sender);
        
        // Burn the repaid IUSD from the user's balance 
        iusdToken.burn(msg.sender, debtRepayment);
        reservePool.decreaseIUSDDebt(debtRepayment);
        
        // burn the gas compensation from the Gas Pool
        iusdToken.burn(address(gasPool), IUSD_GAS_COMPENSATION);
        reservePool.decreaseIUSDDebt(IUSD_GAS_COMPENSATION);
        
        // Send the collateral back to the user
        reservePool.sendETH(msg.sender, collateral);
    }
    
    function _requireCollateralRatioIsAboveMCR(uint256 _collateralRatio) internal pure {
        require(_collateralRatio >= MINIMUN_COLLATERAL_RATIO, "Collateral Ratio Below MINIMUN_COLLATERAL_RATIO");
    }
    
    function _addCollateralToReservePool(uint _amount) internal {
        (bool success, ) = address(reservePool).call{value: _amount}("");
        require(success, "Borrowing: Sending ETH to ReservePool failed");
    }


    

}
