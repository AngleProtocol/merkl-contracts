// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { JsonReader } from "./utils/JsonReader.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { ICore } from "../contracts/interfaces/ICore.sol";
import { CampaignParameters } from "../contracts/struct/CampaignParameters.sol";

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
        address core = readAddress(chainId, "Merkl.CoreMerkl");
        address distributor = readAddress(chainId, "Merkl.Distributor");
        uint256 defaultFees = 0.03 gwei; // 0.03 gwei

        // Deploy implementation
        DistributionCreator implementation = new DistributionCreator();
        console.log("DistributionCreator Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("DistributionCreator Proxy:", address(proxy));

        // Initialize
        DistributionCreator(address(proxy)).initialize(ICore(core), distributor, defaultFees);
    }
}

// SetNewDistributor script
contract SetNewDistributor is DistributionCreatorScript {
    function run(address distributor) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setNewDistributor(distributor);

        console.log("New distributor set to:", distributor);
    }
}

// SetFees script
contract SetFees is DistributionCreatorScript {
    function run(uint256 fees) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setFees(fees);

        console.log("Default fees updated to:", fees);
    }
}

// SetCampaignFees script
contract SetCampaignFees is DistributionCreatorScript {
    function run(uint32 campaignType, uint256 fees) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setCampaignFees(campaignType, fees);

        console.log("Campaign fees updated for type %s to: %s", campaignType, fees);
    }
}

// ToggleTokenWhitelist script
contract ToggleTokenWhitelist is DistributionCreatorScript {
    function run(address token) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).toggleTokenWhitelist(token);

        console.log("Token whitelist toggled for:", token);
    }
}

// RecoverFees script
contract RecoverFees is DistributionCreatorScript {
    function run(IERC20[] calldata tokens, address to) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).recoverFees(tokens, to);

        console.log("Fees recovered to:", to);
    }
}

// SetUserFeeRebate script
contract SetUserFeeRebate is DistributionCreatorScript {
    function run(address user, uint256 rebate) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setUserFeeRebate(user, rebate);

        console.log("Fee rebate set to %s for user: %s", rebate, user);
    }
}

// SetRewardTokenMinAmounts script
contract SetRewardTokenMinAmounts is DistributionCreatorScript {
    function run(address[] calldata tokens, uint256[] calldata amounts) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setRewardTokenMinAmounts(tokens, amounts);

        console.log("Minimum amounts updated for %s tokens", tokens.length);
    }
}

// SetFeeRecipient script
contract SetFeeRecipient is DistributionCreatorScript {
    function run(address recipient) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setFeeRecipient(recipient);

        console.log("Fee recipient updated to:", recipient);
    }
}

// SetMessage script
contract SetMessage is DistributionCreatorScript {
    function run(string calldata message) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).setMessage(message);

        console.log("Message updated to:", message);
    }
}

// ToggleSigningWhitelist script
contract ToggleSigningWhitelist is DistributionCreatorScript {
    function run(address user) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).toggleSigningWhitelist(user);

        console.log("Signing whitelist toggled for user:", user);
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
    function run(bytes calldata signature) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).sign(signature);

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
    function run(CampaignParameters calldata campaign) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

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
    function run(CampaignInput[] calldata inputs) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");
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

        bytes32[] memory campaignIds = creator.createCampaigns(campaigns);

        console.log("Created %s campaigns:", inputsLength);
        for (uint256 i = 0; i < campaignIds.length; i++) {
            console.log("Campaign %s ID: %s", i, vm.toString(campaignIds[i]));
        }
    }
}

// SignAndCreateCampaign script
contract SignAndCreateCampaign is DistributionCreatorScript {
    function run(CampaignParameters calldata campaign, bytes calldata signature) external broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        bytes32 campaignId = DistributionCreator(creatorAddress).signAndCreateCampaign(campaign, signature);

        console.log("Message signed and campaign created with ID:", vm.toString(campaignId));
    }
}
