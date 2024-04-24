import {ethers, hardhatArguments, upgrades} from "hardhat";
import {networks} from "./networks";

export async function upgradeMarketManager(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    const MarketManager = await ethers.getContractFactory("MarketManagerUpgradeable", {
        libraries: {
            ConfigurableUtil: document.deployments.ConfigurableUtil,
            FundingRateUtil: document.deployments.FundingRateUtil,
            LiquidityPositionUtil: document.deployments.LiquidityPositionUtil,
            MarketUtil: document.deployments.MarketUtil,
            PositionUtil: document.deployments.PositionUtil,
        },
    });
    const instance = await ethers.getContractAt(
        "MarketManagerUpgradeable",
        document.deployments.MarketManagerUpgradeable,
    );
    const newInstance = await upgrades.upgradeProxy(instance, MarketManager);
    console.log(`MarketManagerUpgradeable upgraded at ${await newInstance.getAddress()}`);
}

async function main() {
    await upgradeMarketManager((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
