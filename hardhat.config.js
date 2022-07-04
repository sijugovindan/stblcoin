//if (process.env.NODE_ENV !== 'production') {
require('dotenv').config();
//}
require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-truffle5');
require('@nomiclabs/hardhat-ethers');
require("@nomiclabs/hardhat-etherscan");
require('hardhat-gas-reporter');
require('solidity-coverage');
require('@nomiclabs/hardhat-solhint');
require('hardhat-contract-sizer');
require('@openzeppelin/hardhat-upgrades');

//const PRIVATE_KEY = process.env.PRIVATE_KEY;

//const { mnemonic } = require('./secrets.json');
let secret = require('./secrets');

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
/*task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});*/

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "bsctestnet",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    hardhat: {
      forking: {
        url: "https://eth-rinkeby.alchemyapi.io/v2/l4iSN8YR3ltSaBUhF52H1zQ73sOBxCXK"
      }
    },
    bsctestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      gasPrice: 20000000000,
      //accounts: {mnemonic: mnemonic}
      //accounts: [`0x${PRIVATE_KEY}`]
      accounts: [secret.key]
    },
    rinkebytestnet: {
      url: "https://eth-rinkeby.alchemyapi.io/v2/l4iSN8YR3ltSaBUhF52H1zQ73sOBxCXK",
      accounts: [secret.key],
      gas: 10000000
    },
    mainnet: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      gasPrice: 20000000000,
      //accounts: {mnemonic: mnemonic}
      //accounts: [`0x${PRIVATE_KEY}`]
      accounts: [secret.key]
      
    },
    coverage: {
      url: 'http://localhost:8555',
    },
  },
  solidity: {
  //version: '0.6.12',
  version: "0.8.10",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    }
   }
  },
  gasReporter: {
    currency: 'USD',
    enabled: false,
    gasPrice: 50,
  },

  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
    // only: [':ERC20$'],
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 20000
  },
  etherscan: {
    etherscan: {
      //bsc apikey
      apiKey: "BWGG3TB7A6B2ZQXVAGVRYQ7F8XKDAVW9RN",
  
      //eth apikey
      //apiKey: "I1N8KQRB887CTTJRK6N7K4I6M4I8GNP24A",
    },
  },
};