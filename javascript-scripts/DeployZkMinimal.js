import * as fs from "fs";
import { Web3 } from "web3";
import "dotenv/config";
import { ContractFactory, types, Web3ZKsyncL2, ZKsyncPlugin } from "web3-plugin-zksync";

async function main() {
  const web3 = new Web3(/* optional L1 provider */);
  web3.registerPlugin(
    new ZKsyncPlugin(
      Web3ZKsyncL2.initWithDefaultProvider(types.Network.Sepolia)
    )
  );
  const zkSync = web3.ZKsync;
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  const wallet = new zkSync.Wallet(PRIVATE_KEY);
  console.log(`Working with wallet: ${await wallet.getAddress()}`)

  // replace with actual values
  const contractAbi = JSON.parse(fs.readFileSync("./out/ZkSyncMinimalAccount.sol/ZkSyncMinimalAccount.json", "utf8"))["abi"]
  const contractByteCode = JSON.parse(fs.readFileSync("./zkout/ZkSyncMinimalAccount.sol/ZkSyncMinimalAccount.json", "utf8"))["bytecode"]["object"]

  // create a ContractFactory that uses the default create deployment type
  const contractFactory = new ContractFactory(
    contractAbi,
    contractByteCode,
    wallet,
    "createAccount"
  );

  const contract = await contractFactory.deploy();
  console.log("Contract address:", contract.options.address);
  console.log("Contract methods:", contract.methods);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });