// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ContractType } from "@utils/Constants.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { CampaignParameters } from "../contracts/struct/CampaignParameters.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

// Base contract with shared utilities
contract DistributionCreatorScript is BaseScript, JsonReader {
    struct CampaignInput {
        address creator;
        address rewardToken;
        uint256 amount;
        uint32 campaignType;
        uint32 startTimestamp;
        uint32 duration;
        bytes campaignData;
    }
}

// Deploy script
contract Deploy is DistributionCreatorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Read configuration from JSON
        address accessControlManager = readAddress(chainId, "Merkl.CoreMerkl");
        address distributor = readAddress(chainId, "Merkl.Distributor");
        uint256 defaultFees = 0.03 gwei; // 0.03 gwei

        // Deploy implementation
        DistributionCreator implementation = new DistributionCreator();
        console.log("DistributionCreator Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("DistributionCreator Proxy:", address(proxy));

        // Initialize
        DistributionCreator(address(proxy)).initialize(
            IAccessControlManager(accessControlManager),
            distributor,
            defaultFees
        );
    }
}

contract DeployImplementation is DistributionCreatorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Deploy implementation
        DistributionCreator implementation = new DistributionCreator();
        console.log("DistributionCreator Implementation:", address(implementation));
    }
}

// SetNewDistributor script
contract SetNewDistributor is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED DISTRIBUTOR ADDRESS
        address distributor = address(0);
        _run(distributor);
    }

    function run(address distributor) external {
        _run(distributor);
    }

    function _run(address _distributor) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setNewDistributor(_distributor);

        console.log("New distributor set to:", _distributor);
    }
}

// SetFees script
contract SetFees is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED FEES
        uint256 fees = 0;
        _run(fees);
    }

    function run(uint256 fees) external {
        _run(fees);
    }

    function _run(uint256 _fees) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setFees(_fees);

        console.log("Default fees updated to:", _fees);
    }
}

// SetCampaignFees script
contract SetCampaignFees is DistributionCreatorScript {
    function run() external {
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN TYPE AND FEES
        uint32 campaignType = 0;
        uint256 fees = 0;
        _run(campaignType, fees);
    }

    function run(uint32 campaignType, uint256 fees) external {
        _run(campaignType, fees);
    }

    function _run(uint32 _campaignType, uint256 _fees) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setCampaignFees(_campaignType, _fees);

        console.log("Campaign fees updated for type %s to: %s", _campaignType, _fees);
    }
}

// ToggleTokenWhitelist script
contract ToggleTokenWhitelist is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED TOKEN ADDRESS
        address token = address(0);
        _run(token);
    }

    function run(address token) external {
        _run(token);
    }

    function _run(address _token) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).toggleTokenWhitelist(_token);

        console.log("Token whitelist toggled for:", _token);
    }
}

// RecoverFees script
contract RecoverFees is DistributionCreatorScript {
    function run() external {
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKENS AND RECIPIENT
        IERC20[] memory tokens = new IERC20[](0);
        address to = address(0);
        _run(tokens, to);
    }

    function run(IERC20[] calldata tokens, address to) external {
        _run(tokens, to);
    }

    function _run(IERC20[] memory _tokens, address _to) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).recoverFees(_tokens, _to);

        console.log("Fees recovered to:", _to);
    }
}

// SetUserFeeRebate script
contract SetUserFeeRebate is DistributionCreatorScript {
    function run() external {
        // MODIFY THESE VALUES TO SET YOUR DESIRED USER AND REBATE
        address user = address(0);
        uint256 rebate = 0;
        _run(user, rebate);
    }

    function run(address user, uint256 rebate) external {
        _run(user, rebate);
    }

    function _run(address _user, uint256 _rebate) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setUserFeeRebate(_user, _rebate);

        console.log("Fee rebate set to %s for user: %s", _rebate, _user);
    }
}

// SetRewardTokenMinAmounts script
contract SetRewardTokenMinAmounts is DistributionCreatorScript {
    // forge script scripts/DistributionCreator.s.sol:SetRewardTokenMinAmounts --rpc-url bsc --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast -i 1
    function run() external {
        console.log("DEPLOYER_ADDRESS:", broadcaster);
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKENS AND AMOUNTS
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = 0x56fA5F7BF457454Be33D8B978C86A5f5B9DD84C2;
        amounts[0] = 3 * 10 ** 17;
        _run(tokens, amounts);
    }

    function run(address[] calldata tokens, uint256[] calldata amounts) external {
        _run(tokens, amounts);
    }

    function _run(address[] memory _tokens, uint256[] memory _amounts) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setRewardTokenMinAmounts(_tokens, _amounts);

        console.log("Minimum amounts updated for %s tokens", _tokens.length);
    }
}

// SetFeeRecipient script
contract SetFeeRecipient is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED RECIPIENT
        address recipient = address(0);
        _run(recipient);
    }

    function run(address recipient) external {
        _run(recipient);
    }

    function _run(address _recipient) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setFeeRecipient(_recipient);

        console.log("Fee recipient updated to:", _recipient);
    }
}

// SetMessage script
contract SetMessage is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED MESSAGE
        string memory message = "";
        _run(message);
    }

    function run(string calldata message) external {
        _run(message);
    }

    function _run(string memory _message) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setMessage(_message);

        console.log("Message updated to:", _message);
    }
}

// GetMessage script
contract GetMessage is DistributionCreatorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        console.log("Creator address:", creatorAddress);
        string memory message = DistributionCreator(creatorAddress).message();

        console.log("Message is:", message);
    }
}

// ToggleSigningWhitelist script
contract ToggleSigningWhitelist is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED USER ADDRESS
        address user = address(0);
        _run(user);
    }

    function run(address user) external {
        _run(user);
    }

    function _run(address _user) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).toggleSigningWhitelist(_user);

        console.log("Signing whitelist toggled for user:", _user);
    }
}

// AcceptConditions script
contract AcceptConditions is DistributionCreatorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).acceptConditions();

        console.log("Conditions accepted for:", broadcaster);
    }
}

// Sign script
contract Sign is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED SIGNATURE
        bytes memory signature = "";
        _run(signature);
    }

    function run(bytes calldata signature) external {
        _run(signature);
    }

    function _run(bytes memory _signature) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).sign(_signature);

        console.log("Message signed by:", broadcaster);
    }
}

// CreateCampaign script
// @notice Example usage for CreateCampaign:
// forge script scripts/DistributionCreator.s.sol:CreateCampaign \
// --rpc-url lisk \
// --sig "run((bytes32,address,address,uint256,uint32,uint32,uint32,bytes))" \
// "(\
// 0x0000000000000000000000000000000000000000000000000000000000000000,\
// 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701,\
// 0xE0688A2FE90d0f93F17f273235031062a210d691,\
// 2000000000000000000000,\
// 2,\
// 1732924800,\
// 604800,\
// 0x000000000000000000000000ec883424202a963af2a3e59bccaa0219e88ab9db00000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000000000000000000fa00000000000000000000000000000000000000000000000000000000000000fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\
// )"
contract CreateCampaign is DistributionCreatorScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN PARAMETERS
        // address targetToken = address(0xEe9BFf933aDD313C4289E98dA80fEfbF9d5Cd9Ba);
        // uint32 campaignType = 22;
        // uint32 subCampaignType = 0;
        // uint256 tokenId = 0;
        // address[] memory whitelist = new address[](0);
        // address[] memory blacklist = new address[](0);
        // string memory url = "https://app.hyperdrive.box/market/100/0xEe9BFf933aDD313C4289E98dA80fEfbF9d5Cd9Ba";
        // bytes[] memory hooks = new bytes[](0);
        // string memory apr = "1";
        // bool targetTokenPricing = true;
        // bool rewardTokenPricing = false;
        // bytes memory campaignData = abi.encode(
        //     targetToken,
        //     subCampaignType,
        //     tokenId,
        //     whitelist,
        //     blacklist,
        //     url,
        //     hooks,
        //     apr,
        //     targetTokenPricing,
        //     rewardTokenPricing
        // );
        // //

        address targetToken = address(0x004626A008B1aCdC4c74ab51644093b155e59A23);
        uint32 campaignType = 1;
        address[] memory whitelist = new address[](0);
        address[] memory blacklist = new address[](0);
        string memory url = "";
        bytes[] memory forwarders = new bytes[](0);
        bytes[] memory hooks = new bytes[](0);
        bytes memory campaignData = abi.encode(targetToken, whitelist, blacklist, url, forwarders, hooks, hex"");
        // END

        CampaignParameters memory campaign = CampaignParameters({
            campaignId: bytes32(0),
            creator: address(0),
            rewardToken: address(0x65A1DfB54CDec9011688b1818A27A8C687e6B1ed),
            amount: 1e4 * 1e8,
            campaignType: campaignType,
            startTimestamp: uint32(block.timestamp - 5 hours),
            duration: 1 days,
            campaignData: campaignData
        });
        _run(campaign);
    }

    function run(CampaignParameters calldata campaign) external broadcast {
        _run(campaign);
    }

    function _run(CampaignParameters memory campaign) internal {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");
        IERC20(campaign.rewardToken).approve(creatorAddress, campaign.amount);
        bytes32 campaignId = DistributionCreator(creatorAddress).createCampaign(campaign);

        console.log("Campaign created with ID:", vm.toString(campaignId));
    }
}

// @notice Example usage for CreateCampaigns:
// forge script scripts/DistributionCreator.s.sol:CreateCampaigns \
// --rpc-url lisk \
// --sig "run((address,address,uint256,uint32,uint32,uint32,bytes)[])" \
// "[(\
// 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701,\
// 0xE0688A2FE90d0f93F17f273235031062a210d691,\
// 2000000000000000000000,\
// 2,\
// 1732924800,\
// 604800,\
// 0x000000000000000000000000ec883424202a963af2a3e59bccaa0219e88ab9db00000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000000000000000000fa00000000000000000000000000000000000000000000000000000000000000fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\
// )]"
contract CreateCampaigns is DistributionCreatorScript {
    // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN INPUTS
    mapping(uint256 => address[]) public targetTokens;
    uint256 distributionChain = 100;
    uint16[4] public chains = [1, 100, 8453, 59144];
    uint32 public campaignType = 22;
    uint32 public subCampaignType = 0;
    uint256 public tokenId = 0;
    address[] public whitelist = new address[](0);
    address[] public blacklist = new address[](0);
    bytes[] public hooks = new bytes[](0);
    string public apr = "1";
    bool public targetTokenPricing = true;
    bool public rewardTokenPricing = false;
    string public baseUrl = "https://app.hyperdrive.box/market/";
    address public rewardToken = 0x79385D4B4c531bBbDa25C4cFB749781Bd9E23039;

    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN INPUTS
        uint256 amount = 1e6 * 10 ** (IERC20Metadata(rewardToken).decimals());
        targetTokens[1] = [
            0xd7e470043241C10970953Bd8374ee6238e77D735
            // 0x324395D5d835F84a02A75Aa26814f6fD22F25698,
            // 0xca5dB9Bb25D09A9bF3b22360Be3763b5f2d13589,
            // 0xd41225855A5c5Ba1C672CcF4d72D1822a5686d30,
            // 0xA29A771683b4857bBd16e1e4f27D5B6bfF53209B,
            // 0x4c3054e51b46BE3191be9A05e73D73F1a2147854,
            // 0x158Ed87D7E529CFE274f3036ade49975Fb10f030,
            // 0xc8D47DE20F7053Cc02504600596A647A482Bbc46,
            // 0x7548c4F665402BAb3a4298B88527824B7b18Fe27,
            // 0xA4090183878d5B7b6Ad104863743dd7E58985321,
            // 0x8f2AC104e07d94488a1821E5A393351FCA9239aa,
            // 0x05b65FA90AD702e6Fd0C3Bd7c4c9C47BAB2BEa6b,
            // 0xf1232Dc21eADAf503D82f1e1361CfF2BBf40394D
        ];
        targetTokens[100] = [
            0x2f840f1575EE77adAa43415Ac5953F7Db9F8C6ba,
            0xEe9BFf933aDD313C4289E98dA80fEfbF9d5Cd9Ba,
            0x9248f874AaA2c53AD9324d7A2D033ea133443874
        ];
        // targetTokens[8453] = [
        //     0x2a1ca35Ded36C531F77c614b5AAA0d4F86edbB06,
        //     0xFcdaF9A4A731C24ed2E1BFd6FA918d9CF7F50137,
        //     0x1243C06146ACa2D4Aaf8F9860F6D8d59d636d46C,
        //     0xceD9F810098f8329472AEFbaa1112534E96A5c7b,
        //     0x9bAdB6A21FbA04EE94fde3E85F7d170E90394c89,
        //     0xD9b66D9a819B36ECEfC26B043eF3B422d5A6123a,
        //     0xdd8E1B14A04cbdD98dfcAF3F0Db84A80Bfb8FC25
        // ];
        // targetTokens[59144] = [0xB56e0Bf37c4747AbbC3aA9B8084B0d9b9A336777, 0x1cB0E96C07910fee9a22607bb9228c73848903a3];

        CampaignInput[] memory inputs;
        uint256 countInputs = 0;
        {
            uint256 numberCampaigns = 0;
            for (uint256 i = 0; i < chains.length; i++) {
                numberCampaigns += targetTokens[chains[i]].length;
            }
            inputs = new CampaignInput[](numberCampaigns);
        }
        for (uint256 i = 0; i < chains.length; i++) {
            uint256 chainId = chains[i];
            string memory baseUrlChain = string.concat(baseUrl, vm.toString(chainId), "/");
            address[] memory tokens = targetTokens[chainId];
            for (uint256 j = 0; j < tokens.length; j++) {
                bytes memory campaignData = abi.encode(
                    tokens[j],
                    subCampaignType,
                    tokenId,
                    whitelist,
                    blacklist,
                    string.concat(baseUrlChain, vm.toString(tokens[j])),
                    hooks,
                    apr,
                    targetTokenPricing,
                    rewardTokenPricing
                );
                campaignData = abi.encode(uint32(chainId), campaignData);
                campaignData = abi.encodePacked(campaignData, hex"c0c0c0c0");
                inputs[countInputs++] = CampaignInput({
                    creator: address(0),
                    rewardToken: rewardToken,
                    amount: amount,
                    campaignType: campaignType,
                    startTimestamp: 1738195200,
                    duration: 30 days,
                    campaignData: campaignData
                });
            }
        }

        _run(inputs);
    }

    function run(CampaignInput[] calldata inputs) external broadcast {
        _run(inputs);
    }

    function _run(CampaignInput[] memory inputs) internal {
        address creatorAddress = readAddress(block.chainid, "Merkl.DistributionCreator");
        DistributionCreator creator = DistributionCreator(creatorAddress);

        uint256 inputsLength = inputs.length;
        CampaignParameters[] memory campaigns = new CampaignParameters[](inputsLength);

        // Convert inputs to CampaignParameters, letting the contract compute campaignId
        for (uint256 i = 0; i < inputsLength; i++) {
            campaigns[i] = CampaignParameters({
                creator: inputs[i].creator,
                rewardToken: inputs[i].rewardToken,
                amount: inputs[i].amount,
                campaignType: inputs[i].campaignType,
                startTimestamp: inputs[i].startTimestamp,
                duration: inputs[i].duration,
                campaignData: inputs[i].campaignData,
                campaignId: bytes32(0) // Will be computed by the contract
            });
        }

        IERC20(rewardToken).approve(creatorAddress, inputs.length * inputs[0].amount);
        bytes32[] memory campaignIds = creator.createCampaigns(campaigns);

        console.log("Created %s campaigns:", inputsLength);
        for (uint256 i = 0; i < campaignIds.length; i++) {
            console.log("Campaign %s ID: %s", i, vm.toString(campaignIds[i]));
        }
    }
}

contract OverrideCampaign is DistributionCreatorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN PARAMETERS
        bytes32 campaignId = 0xf93a5b762bd5a2a3e6cf6dcb83cb54f70ab2de457e0dc4cbb4da29ba8b54e4ad;
        address targetToken = address(0x1337BedC9D22ecbe766dF105c9623922A27963EC);
        address[] memory whitelist = new address[](0);
        address[] memory blacklist = new address[](0);
        string memory url = "https://curve.fi/dex/#/xdai/pools/3pool/deposit";
        bytes[] memory forwarders = new bytes[](0);
        bytes[] memory hooks = new bytes[](0);
        // END

        CampaignParameters memory campaign = DistributionCreator(creatorAddress).campaign(campaignId);

        CampaignParameters memory overrideCampaign = CampaignParameters({
            campaignId: bytes32(campaign.campaignId),
            creator: address(0),
            rewardToken: address(0x65A1DfB54CDec9011688b1818A27A8C687e6B1ed),
            amount: campaign.amount,
            campaignType: 1,
            startTimestamp: uint32(campaign.startTimestamp),
            duration: 1.5 days,
            campaignData: abi.encode(targetToken, whitelist, blacklist, url, forwarders, hooks, hex"")
        });
        _run(overrideCampaign);
    }

    function run(CampaignParameters calldata campaign) external broadcast {
        _run(campaign);
    }

    function _run(CampaignParameters memory campaign) internal {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");
        IERC20(campaign.rewardToken).approve(creatorAddress, campaign.amount);
        DistributionCreator(creatorAddress).overrideCampaign(campaign.campaignId, campaign);

        console.log("Campaign created with ID:", vm.toString(campaign.campaignId));
    }
}

contract ReallocateCampaign is DistributionCreatorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN PARAMETERS
        bytes32 campaignId = 0x490af89ce201bb272809983117aa95ce4a6cfcbb178343076519fc80ec2ff408;
        address[] memory froms = new address[](2);
        froms[0] = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        froms[1] = 0x53C9ACaB7D5f3078141D1178EeA782c7129D92C9;
        address to = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        // END

        _run(campaignId, froms, to);
    }

    function run(bytes32 campaignId, address[] memory froms, address to) external broadcast {
        _run(campaignId, froms, to);
    }

    function _run(bytes32 campaignId, address[] memory froms, address to) internal {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");
        DistributionCreator(creatorAddress).reallocateCampaignRewards(campaignId, froms, to);
    }
}

// CreateCampaign script
contract CreateCampaignTest is DistributionCreatorScript {
    function run() external {
        vm.createSelectFork(vm.envString("BASE_NODE_URI"));
        uint256 chainId = block.chainid;

        /// TODO: COMPLETE
        IERC20 rewardToken = IERC20(0xC011882d0f7672D8942e7fE2248C174eeD640c8f);
        uint256 amount = 100 ether;
        /// END

        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");
        DistributionCreator distributionCreator = DistributionCreator(creatorAddress);

        vm.startBroadcast(broadcaster);

        MockToken(address(rewardToken)).mint(broadcaster, amount);
        rewardToken.approve(address(distributionCreator), amount);

        uint32 startTimestamp = uint32(block.timestamp + 600);

        bytes32 campaignId = distributionCreator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: broadcaster,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );
        vm.stopBroadcast();

        CampaignParameters memory campaign = distributionCreator.campaign(campaignId);
        require(campaign.creator == broadcaster, "Invalid creator");
        require(campaign.rewardToken == address(rewardToken), "Invalid reward token");
        require(campaign.amount == (amount * (1e9 - distributionCreator.defaultFees())) / 1e9, "Invalid amount");
        require(campaign.campaignType == 1, "Invalid campaign type");
        require(campaign.startTimestamp == startTimestamp, "Invalid start timestamp");
        require(campaign.duration == 3600 * 24, "Invalid duration");

        console.log("Campaign created with ID:", vm.toString(campaignId));
    }
}

// SignAndCreateCampaign script
contract SignAndCreateCampaign is DistributionCreatorScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN PARAMETERS AND SIGNATURE
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: bytes32(0),
            creator: address(0),
            rewardToken: address(0),
            amount: 0,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp),
            duration: 7 days,
            campaignData: ""
        });
        bytes memory signature = "";
        _run(campaign, signature);
    }

    function run(CampaignParameters calldata campaign, bytes calldata signature) external broadcast {
        _run(campaign, signature);
    }

    function _run(CampaignParameters memory campaign, bytes memory signature) internal {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        bytes32 campaignId = DistributionCreator(creatorAddress).signAndCreateCampaign(campaign, signature);

        console.log("Message signed and campaign created with ID:", vm.toString(campaignId));
    }
}

contract UpgradeAndBuildUpgradeToPayload is DistributionCreatorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address distributionCreator = readAddress(chainId, "Merkl.DistributionCreator");

        address distributionCreatorImpl = address(new DistributionCreator());

        bytes memory payload = abi.encodeWithSelector(
            ITransparentUpgradeableProxy.upgradeTo.selector,
            distributionCreatorImpl
        );

        try this.externalReadAddress(chainId, "AngleLabs") returns (address safe) {
            _serializeJson(
                chainId,
                distributionCreator, // target address (the proxy)
                0, // value
                payload, // direct upgrade call
                Operation.Call, // standard call (not delegate)
                hex"", // signature
                safe // safe address
            );
        } catch {}
    }

    function externalReadAddress(uint256 chainId, string memory key) external view returns (address) {
        return readAddress(chainId, key);
    }
}

contract SetRewardTokenMinAmountsDistributor is DistributionCreatorScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN PARAMETERS AND SIGNATURE
        address[] memory tokens = new address[](1);
        uint256[] memory minAmounts = new uint256[](1);
        tokens[0] = 0x79385D4B4c531bBbDa25C4cFB749781Bd9E23039;
        minAmounts[0] = 1e18;

        _run(tokens, minAmounts);
    }

    function run(address[] memory tokens, uint256[] memory minAmounts) external broadcast {
        _run(tokens, minAmounts);
    }

    function _run(address[] memory tokens, uint256[] memory minAmounts) internal {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setRewardTokenMinAmounts(tokens, minAmounts);
    }
}
