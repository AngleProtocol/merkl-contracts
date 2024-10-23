import * as readline from "readline";
import type { DeployFunction } from "hardhat-deploy/types";
import yargs from "yargs";

import { CoreBorrow__factory } from "@angleprotocol/sdk";
import {
	type DistributionCreator,
	DistributionCreator__factory,
} from "../typechain";
import { parseAmount } from "../utils/bignumber";
const argv = yargs.env("").boolean("ci").parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
	const { deploy } = deployments;
	const { deployer } = await ethers.getNamedSigners();


	let core: string;
	core = "0x1746f9bb465d3747fe9C2CfE7759F4B871a06d3C";
	const coreContract = new ethers.Contract(
		core,
		CoreBorrow__factory.createInterface(),
		deployer,
	) as any;
	if (
		(await coreContract.GOVERNOR_ROLE()) !=
		"0x7935bd0ae54bc31f548c14dba4d37c5c64b3f8ca900cb468fb8abd54d5894f55"
	)
		throw "Invalid Core Merkl";


	if (deployer.address !== "0x9f76a95AA7535bb0893cf88A146396e00ed21A12")
		throw `Invalid deployer address: ${deployer.address}`;

	/*
  if (!network.live) {
    // If we're in mainnet fork, we're using the `CoreBorrow` address from mainnet
    core = registry(ChainId.MAINNET)?.Merkl?.CoreMerkl!;
  } else {
    // Otherwise, we're using the proxy admin address from the desired network
    core = registry(network.config.chainId as ChainId)?.Merkl?.CoreMerkl!;
  }
  */

	console.log(deployer.address);
	console.log("Now deploying DistributionCreator");
	console.log("Starting with the implementation");
	console.log("deployer ", await deployer.getBalance());
	await deploy("DistributionCreator_Implementation_V2_0", {
		contract: "DistributionCreator",
		from: deployer.address,
		log: !argv.ci,
	});

	const implementationAddress = (
		await ethers.getContract("DistributionCreator_Implementation_V2_0")
	).address;

	console.log(
		`Successfully deployed the implementation for DistributionCreator at ${implementationAddress}`,
	);
	console.log("");

	const distributor = (await deployments.get("Distributor")).address;
	console.log("Now deploying the Proxy");

	await deploy("DistributionCreator", {
		contract: "ERC1967Proxy",
		from: deployer.address,
		args: [implementationAddress, "0x"],
		log: !argv.ci,
	});

	const manager = (await deployments.get("DistributionCreator")).address;
	console.log(`Successfully deployed contract at the address ${manager}`);
	console.log("Initializing the contract");
	const contract = new ethers.Contract(
		manager,
		DistributionCreator__factory.createInterface(),
		deployer,
	) as DistributionCreator;

	await (
		await contract
			.connect(deployer)
			.initialize(core, distributor, parseAmount.gwei("0.03"))
	).wait();
	console.log("Contract successfully initialized");
	console.log("");
	console.log(await contract.core());

	/* Once good some functions need to be called to have everything setup.

  In the `DistributionCreator` contract:
  - `setRewardTokenMinAmounts`
  - `setFeeRecipient -> angleLabs
  - `setMessage` ->

  In the Distributor contract:
  - `toggleTrusted` -> keeper bot updating
  - `setDisputeToken` -> should we activate dispute periods
  - `setDisputePeriod`
  - `setDisputeAmount`
  */
};

func.tags = ["distributionCreator"];
func.dependencies = ["distributor"];
export default func;
