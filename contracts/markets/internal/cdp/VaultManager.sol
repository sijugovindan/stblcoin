// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../../external/price/PriceFeed.sol";
import "../../../PrimaryMarket.sol";
import "../../../helpers/Base.sol";
import "../../../tokens/stablecoins/IdeaUSD.sol";
import "./SortedVaults.sol";

// Pools 
import "../pools/ReservePool.sol";
import "../pools/StableCoinPool.sol";
import "../pools/GasPool.sol";
import "../pools/StakingPool.sol";

//import "hardhat/console.sol";

contract VaultManager is Base, Ownable {
    PriceFeed public priceFeed;
    PrimaryMarket public primaryMarket;    
    IdeaUSD public iusdToken;
    SortedVaults public sortedVaults;

    // Pools
    StableCoinPool public stableCoinPool;
    ReservePool public reservePool;
    GasPool public gasPool;
    StakingPool public stakingPool;
    
    uint256 public baseRate;

    // latest fee operation (redemption or new IUSD issuance)
    uint256 public lastFeeOperationTime;
    
    enum Status {
        nonExistent, // 0
        active,  // 1
        closedByOwner, // 2
        closedByLiquidation, // 3
        closedByRedemption // 4
    }

    // Store the necessary data for a Vault
    struct Vault {
        uint debt;
        uint collateral;
        Status status;
    }

    mapping (address => Vault) public vaults;

    function setAddresses(PriceFeed _priceFeed, IdeaUSD _IUSDToken, StableCoinPool _stableCoinPool, GasPool _gasPool, StakingPool _stakingPool, ReservePool _reservePool) external onlyOwner {
            
        primaryMarket = PrimaryMarket(msg.sender);
        priceFeed = _priceFeed;
        iusdToken = _IUSDToken;
        sortedVaults = new SortedVaults(msg.sender);
        
        // pools
        reservePool = _reservePool;
        stableCoinPool = _stableCoinPool;    
        gasPool = _gasPool;
        stakingPool = _stakingPool;
        
        renounceOwnership();
    }
    
    function liquidate(address _borrower) external {
        uint256 price = priceFeed.getPrice();
        console.log("Price %s", price);
        
        // get vault info
        (uint256 currentReserve, uint256 currentIUSDDebt) = _getCurrentTroveAmounts(_borrower);
        console.log("currentReserve %s", currentReserve);
        console.log("currentIUSDDebt %s", currentIUSDDebt);

        uint256 collateralRatio = StableCoinMath._computeCR(currentReserve, currentIUSDDebt, price);
        console.log("collateralRatio %s", collateralRatio);
        
        require(collateralRatio < MINIMUN_COLLATERAL_RATIO, "Cannot liquidate vault");
        
        uint256 iusdInStableCoinPool = stableCoinPool.getTotalIUSDDeposits();
        require(iusdInStableCoinPool >= currentIUSDDebt, "Insufficient funds to liquidate");
        
        // calculate collateral compensation
        uint256 collateralCompensation = currentReserve / PERCENT_DIVISOR; // to get 5 %
        uint256 gasCompensation = IUSD_GAS_COMPENSATION;
        uint256 collateralToLiquidate = currentReserve - collateralCompensation;
        
        // update debt  
        reservePool.decreaseIUSDDebt(currentIUSDDebt);
        
        // update debt + burn tokens 
        stableCoinPool.offset(currentIUSDDebt);
        
        // send liquidated reserve/BNB to stableCoinPool
        reservePool.sendReserve(address(stableCoinPool), collateralToLiquidate);
        
        // close vault 
        _closeVault(_borrower, Status.closedByLiquidation);
        
        // send gas compensation 
        iusdToken.transferFrom(address(gasPool), msg.sender, gasCompensation);
        
        // send reserve liquidated (0.5%) to liquidator 
        reservePool.sendReserve(msg.sender, collateralCompensation);
    }
    
    function redemption(uint256 _amountToRedeem) external {
        require(iusdToken.balanceOf(msg.sender) >= _amountToRedeem, "VaultManager: Requested redemption amount must be <= user's IUSD token balance");
        
        uint256 price = priceFeed.getPrice();
        console.log("Price %s", price);
        
        // mention that this case in liquity is more complex but for learning purposes we are simplifying, we will just redeem the last one,
        // also mention that in reality liquity would go throught all the troves till the amount of IUSD that is redeemed is complete 
        address borrowerToRedeemFrom = sortedVaults.getLast();
        
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Vault minus the liquidation reserve
        uint256 maxAmounToRedeem = StableCoinMath._min(_amountToRedeem, vaults[msg.sender].debt - IUSD_GAS_COMPENSATION);
        console.log("IUSD to redeem %s", maxAmounToRedeem);
        
        // Get the ReserveLot of equivalent value in USD
        uint256 reserveToRedeem = maxAmounToRedeem * DECIMAL_PRECISION / price;
        console.log("reserve to redeem %s", reserveToRedeem);
        
        // Decrease the debt and collateral of the current Vault according to the IUSD lot and corresponding Reserve to send
        uint newDebt = vaults[borrowerToRedeemFrom].debt - maxAmounToRedeem;
        uint newCollateral = vaults[borrowerToRedeemFrom].collateral - reserveToRedeem;
        console.log("newDebt %s", newDebt);
        console.log("newCollateral %s", newCollateral);
        
        uint256 totalSystemDebt = reservePool.getIUSDDebt();
        console.log("totalSystemDebt %s", totalSystemDebt);
        
        if (newDebt == IUSD_GAS_COMPENSATION) {
            // close vault
            _closeVault(borrowerToRedeemFrom, Status.closedByRedemption);
        } else {
            uint newNICR = StableCoinMath._computeNominalCR(newCollateral, newDebt);
            sortedVaults.reInsert(borrowerToRedeemFrom, newNICR);
            console.log("Old debt %s", vaults[borrowerToRedeemFrom].debt);
            console.log("Old collateral %s", vaults[borrowerToRedeemFrom].collateral);
            
            vaults[borrowerToRedeemFrom].debt = newDebt;
            vaults[borrowerToRedeemFrom].collateral = newCollateral;
        }
        
         // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total IUSD supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(reserveToRedeem, price, totalSystemDebt);

        // Calculate the redemption fee in Reserve
        uint256 reserveFee = _getRedemptionFee(reserveToRedeem);
        console.log("reserveFee %s", reserveFee);
        
        // Send the Reserve fee to the LQTY staking contract
        reservePool.sendReserve(address(stakingPool), reserveFee);
        stakingPool.increaseReserveFees(reserveFee);

        uint256 reserveToSendToRedeemer = reserveToRedeem - reserveFee;
        console.log("reserveToSendToRedeemer %s", reserveToSendToRedeemer);
       
        // Burn the total IUSD that is cancelled with debt
        iusdToken.burn(msg.sender, maxAmounToRedeem);
        
        // Update Active Pool IUSD
        reservePool.decreaseIUSDDebt(maxAmounToRedeem);
        
        // send Reserve to redeemer
        reservePool.sendReserve(msg.sender, reserveToSendToRedeemer);
    }
    
    function _updateBaseRateFromRedemption(uint _ReserveDrawn,  uint _price, uint _totalIUSDSupply) internal returns (uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn Reserve back to IUSD at face value rate (1 IUSD:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedIUSDFraction = (_ReserveDrawn * _price) / _totalIUSDSupply;

        uint newBaseRate = decayedBaseRate + (redeemedIUSDFraction / BETA);
        newBaseRate = StableCoinMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%

        baseRate = newBaseRate;

        _updateLastFeeOpTime();

        return newBaseRate;
    }
    
    function _getRedemptionFee(uint _ReserveDrawn) internal view returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _ReserveDrawn);
    }
    
    function _calcRedemptionFee(uint _redemptionRate, uint _ReserveDrawn) internal pure returns (uint) {
        uint redemptionFee = _redemptionRate * _ReserveDrawn / DECIMAL_PRECISION;
        require(redemptionFee < _ReserveDrawn, "TroveManager: Fee would eat up all returned collateral");
        return redemptionFee;
    }
    
    function getRedemptionRate() public view returns (uint) {
        return _calcRedemptionRate(baseRate);
    }
    
    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return StableCoinMath._min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }
    
    // Return the nominal collateral ratio (ICR) of a given Trove, without the price. Takes a trove's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address _borrower) public view returns (uint) {
        (uint currentReserve, uint currentIUSDDebt) = _getCurrentTroveAmounts(_borrower);

        uint NICR = _computeNominalCR(currentReserve, currentIUSDDebt);
        return NICR;
    }
    
    function _computeNominalCR(uint _coll, uint _debt) internal pure returns (uint) {
        if (_debt > 0) {
            return _coll * NICR_PRECISION / _debt;
        }
        // Return the maximal value for uint256 if the Trove has a debt of 0. Represents "infinite" CR.
        else { // if (_debt == 0)
            return 2**256 - 1;
        }
    }
    
    function _getCurrentTroveAmounts(address _borrower) internal view returns (uint, uint) {
        uint currentReserve = vaults[_borrower].collateral;
        uint currentIUSDDebt = vaults[_borrower].debt;

        return (currentReserve, currentIUSDDebt);
    }
    
    // Updates the baseRate state variable based on time elapsed since the last redemption or IUSD PrimaryMarket operation.
    function decayBaseRateFromBorrowing()  external {  
        // external onlyPrimaryMarketContract {
        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION);  // The baseRate can decay to 0

        baseRate = decayedBaseRate;

        _updateLastFeeOpTime();
    }
    
    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        console.log("MinutesPassed %s", minutesPassed);
        
        uint decayFactor = StableCoinMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate * decayFactor / DECIMAL_PRECISION;
    }
    
    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
        }
    }
    
    function getBorrowingFee(uint _IUSDDebt) external view returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _IUSDDebt);
    }
    
    function _calcBorrowingFee(uint _borrowingRate, uint _IUSDDebt) internal pure returns (uint) {
        return _borrowingRate * _IUSDDebt / DECIMAL_PRECISION;
    }
    
    function getBorrowingRate() public view returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function _calcBorrowingRate(uint _baseRate) internal pure returns (uint) {
        return StableCoinMath._min(
            BORROWING_FEE_FLOOR + _baseRate,
            MAX_BORROWING_FEE
        );
    }
    
    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return block.timestamp - lastFeeOperationTime / SECONDS_IN_ONE_MINUTE;
    } 
    
    // --- Vault property getters ---
    function getVaultDebt(address _borrower) external view returns (uint) {
        return vaults[_borrower].debt;
    }

    function getVaultCollateral(address _borrower) external view returns (uint) {
        return vaults[_borrower].collateral;
    }

    // --- Vault property setters, called by BorrowingContract ---
    function createVault(
        address _borrower, 
        uint _collateral, 
        uint256 _debt, 
        uint _status
    ) 
    external 
    onlyPrimaryMarketContract 
    {
        vaults[_borrower].status = Status(_status);   
        vaults[_borrower].collateral = _collateral;
        vaults[_borrower].debt = _debt;
        
        sortedVaults.insert(_borrower, getNominalICR(_borrower));
    }
    
    function closeVault(address _borrower) external onlyPrimaryMarketContract {
        _closeVault(_borrower, Status.closedByOwner);    
    }
    
    function _closeVault(address _borrower, Status closedStatus) internal {
        vaults[_borrower].status = closedStatus;
        vaults[_borrower].collateral = 0;
        vaults[_borrower].debt = 0;

        sortedVaults.remove(_borrower);
    }
    
    modifier onlyPrimaryMarketContract {
        require(msg.sender == address(primaryMarket), "VaultManager: Caller is not the Borrowing contract");
        _;
    }
}
