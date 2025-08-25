import * as fs from "fs";
import { Web3 } from "web3";
import { Web3ZKsyncL2, ZKsyncPlugin, EIP712Signer } from "web3-plugin-zksync";
import "dotenv/config";
import { DEFAULT_GAS_PER_PUBDATA_LIMIT } from "web3-plugin-zksync/lib/constants.js";
import { Provider, SmartAccount, types } from "zksync-ethers";
import { AbiCoder } from "ethers";

// Mainnet
// const ZK_MINIMAL_ADDRESS = ""
// Sepolia
// const ZK_MINIMAL_ADDRESS = ""
// Local
// Update this!
const ZK_MINIMAL_ADDRESS = "0x196bf06Fc207F5efE412635302A9e03a69387E33";

// Update this too!
const RANDOM_APPROVER = "0xed1E24DFfF97892F55361641f1F47Eb992E7ef6D";

// Mainnet
// const USDC_ZKSYNC = "0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4"
// Sepolia
const USDC_ZKSYNC = "0x5249Fd99f1C1aE9B04C65427257Fc3B8cD976620";
// Local
// let USDC_ZKSYNC = ""

const AMOUNT_TO_APPROVE = "1000000";

async function main() {
  console.log("Let's do this!");

  // Local net
  // let provider = new Provider("http://127.0.0.1:8011")
  // let wallet = new Wallet(process.env.PRIVATE_KEY!)

  // // Sepolia - Uncomment to use
  const web3 = new Web3(process.env.ZKSYNC_SEPOLIA_RPC_URL);
  web3.registerPlugin(
    new ZKsyncPlugin(
      Web3ZKsyncL2.initWithDefaultProvider(types.Network.Sepolia)
    )
  );
  const zkSync = web3.ZKsync;
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  const wallet = new zkSync.Wallet(PRIVATE_KEY);
  console.log(`Working with wallet: ${await wallet.getAddress()}`);

  // // Mainnet - Uncomment to use
  // let provider = new Provider(process.env.ZKSYNC_RPC_URL!)
  // const encryptedJson = fs.readFileSync(".encryptedKey.json", "utf8")
  // let wallet = Wallet.fromEncryptedJsonSync(
  //     encryptedJson,
  //     process.env.PRIVATE_KEY_PASSWORD!
  // )

  const abi = JSON.parse(fs.readFileSync("./out/ZkSyncMinimalAccount.sol/ZkSyncMinimalAccount.json", "utf8"))["abi"];
  console.log("Setting up contract details...");
  const zkMinimalAccount = new wallet.provider.eth.Contract(abi, ZK_MINIMAL_ADDRESS);

  // If this doesn't log the owner, you have an issue!
  console.log(`The owner of this minimal account is: `, await zkMinimalAccount.methods.owner().call());
  const usdcAbi = JSON.parse(fs.readFileSync("./out/ERC20.sol/ERC20.json", "utf8"))["abi"];
  const usdcContract = new wallet.provider.eth.Contract(usdcAbi, USDC_ZKSYNC);

  console.log("Populating transaction...");
  const approvalData = await usdcContract.methods.approve(
    RANDOM_APPROVER,
    AMOUNT_TO_APPROVE
  ).encodeABI();

  let aaTx = approvalData;

  const gasLimit = await wallet.provider.estimateGas({
    ...aaTx,
    from: wallet.address
  });
  const gasPrice = await wallet.provider.eth.getGasPrice();

  aaTx = {
    ...aaTx,
    from: ZK_MINIMAL_ADDRESS,
    to: USDC_ZKSYNC,
    gasLimit: gasLimit,
    gasPrice: gasPrice,
    maxFeePerGas: 21000,
    maxPriorityFeePerGas: 0,
    chainId: await wallet.provider.eth.getChainId(),
    nonce: await wallet.provider.eth.getTransactionCount(ZK_MINIMAL_ADDRESS),
    type: 113,
    customData: {
      gasPerPubdata: DEFAULT_GAS_PER_PUBDATA_LIMIT
    },
    value: BigInt(0)
  };
  const signedTxHash = EIP712Signer.getSignedDigest(aaTx)

  console.log("Signing transaction...")
  // const signature = utils.concat([
  //   utils.Signature.from(wallet.signingKey.sign(signedTxHash)).serialized,
  // ])
  const signature = web3.eth.accounts.sign(PRIVATE_KEY, signedTxHash).signature
  console.log(signature)

  aaTx.customData = {
    ...aaTx.customData,
    customSignature: signature,
  }

  console.log(
    `The minimal account nonce before the first tx is ${await wallet.provider.eth.getTransactionCount(
      ZK_MINIMAL_ADDRESS,
    )}`,
  )

  // const rawTx = await zkSync.encodeTransaction(aaTx);
  // const signedTx = await web3.eth.accounts.signTransaction(aaTx, PRIVATE_KEY);
  // const tx = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

  // console.log("Tx sent:", txHashSent);
  // const sentTx = await wallet.provider.eth.broadcastTransaction(
  //   types.Transaction.from(aaTx).serialized,
  // )

  // console.log(`Transaction sent from minimal account with hash ${sentTx.hash}`)
  // await tx.wait()

  // const provider = new Provider(process.env.ZKSYNC_SEPOLIA_RPC_URL);
  let tx = {
    // to: USDC_ZKSYNC,
    value: BigInt(0),
    gasPrice,
    gasLimit: BigInt(20000000),
    chainId: await wallet.provider.eth.getChainId(),
    nonce: await wallet.provider.eth.getTransactionCount(ZK_MINIMAL_ADDRESS),
  };

  // const abiCoder = new AbiCoder();
  // const aaSignature = abiCoder.encode(
  //   ['string', 'string'],
  //   ['hello', 'world']
  // );

  tx.from = ZK_MINIMAL_ADDRESS;
  tx.type = 113;
  tx.customData = {
    ...tx.customData,
    customSignature: approvalData,
  };
  const sentTx = await zkSync.broadcastTransaction(
    types.Transaction.from(tx).serialized
  );
  await sentTx.wait();

  // Checking that the nonce for the account has increased
  console.log(
    `The account's nonce after the first tx is ${await wallet.provider.eth.getTransactionCount(
      ZK_MINIMAL_ADDRESS,
    )}`,
  )
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });