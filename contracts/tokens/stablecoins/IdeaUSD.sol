// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IdeaUSD is ERC20 {
    address public primaryMarket; 
    address public vaultManagerAddress;
    address public stabilityPoolAddress;
    
    constructor(
        address _vaultManagerAddress, 
        address _stabilityPoolAddress
    ) ERC20("IUSDToken", "IUSDToken")
    {
        primaryMarket = msg.sender;    
        vaultManagerAddress = _vaultManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
    }
    
    function mint(address _account, uint256 _amount) external onlyPrimaryMarket{
        _mint(_account, _amount);
    }
    
    
    function burn(address _account, uint256 _amount) external onlyPrimaryMarketOrVaultManagerOrStabilityPool{
        _burn(_account, _amount);
    }
    
    modifier onlyPrimaryMarketOrVaultManagerOrStabilityPool {
        require(msg.sender == primaryMarket || msg.sender == vaultManagerAddress || msg.sender == stabilityPoolAddress, "Invalid minter");
        _;
    }
    
    modifier onlyPrimaryMarket {
        require(msg.sender == primaryMarket, "Invalid minter");
        _;
    }
    
}