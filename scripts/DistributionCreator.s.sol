// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

// Upgrade implementation
contract SetNewImplementation is DistributionCreatorScript {
    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED DISTRIBUTOR ADDRESS
        address newImplementation = address(0x4b19d0db3de20f038417474C5CA4D222c50872b7);
        _run(newImplementation);
    }

    function _run(address newImplementation) internal broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        DistributionCreator(creatorAddress).upgradeTo(newImplementation);

        console.log("New implementation set to:", newImplementation);
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
    function run() external {
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKENS AND AMOUNTS
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);
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
    function run() public broadcast {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        string memory message = DistributionCreator(creatorAddress).message();

        console.log("Message updated to:", message);
    }
}

// CampaignList script
contract GetCampaign is DistributionCreatorScript {
    function run() public {
        uint256 chainId = block.chainid;
        address creatorAddress = readAddress(chainId, "Merkl.DistributionCreator");

        // DistributionCreator(creatorAddress).campaign(
        //     0x49df7e2ba1acc490050523d98e7e960084d873865698aa2e4ccd52fe5a4b4548
        // );

        (bytes32 campaignId, , , , , , , ) = DistributionCreator(creatorAddress).campaignList(836);

        bytes
            memory data = hex"82ad56cb0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000008bb4c975ff3c250e0ceea271728547f3802b36fd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000244912c658000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        payable(address(0xcA11bde05977b3631167028862bE2a173976CA11)).call(data);
        console.logBytes32(campaignId);
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
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: bytes32(0),
            creator: address(0),
            rewardToken: address(0xCe59e272946458dA50C36Ca1E731ED6C5752669F),
            amount: 50000 ether,
            startTimestamp: uint32(block.timestamp + 2 * 3600),
            duration: 2 days,
            campaignType: 10,
            campaignData: abi.encode(
                0x1Fa916C27c7C2c4602124A14C77Dbb40a5FF1BE8,
                1,
                4,
                new address[](0),
                new address[](0),
                hex""
            )
        });
        console.logBytes(campaign.campaignData);
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
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED CAMPAIGN INPUTS
        CampaignInput[] memory inputs = new CampaignInput[](1);
        inputs[0] = CampaignInput({
            creator: address(0),
            rewardToken: address(0),
            amount: 0,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp),
            duration: 7 days,
            campaignData: ""
        });
        _run(inputs);
    }

    function run(CampaignInput[] calldata inputs) external broadcast {
        _run(inputs);
    }

    function _run(CampaignInput[] memory inputs) internal {
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
        address broadcasterAddress = vm.addr(broadcaster);

        MockToken(address(rewardToken)).mint(broadcasterAddress, amount);
        rewardToken.approve(address(distributionCreator), amount);

        uint32 startTimestamp = uint32(block.timestamp + 600);

        bytes32 campaignId = distributionCreator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: broadcasterAddress,
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
        require(campaign.creator == broadcasterAddress, "Invalid creator");
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
    function run() external {
        uint256 chainId = block.chainid;
        address distributionCreator = readAddress(chainId, "Merkl.DistributionCreator");

        address distributionCreatorImpl = address(new DistributionCreator());

        bytes memory payload = abi.encodeWithSelector(
            ITransparentUpgradeableProxy.upgradeTo.selector,
            distributionCreatorImpl
        );

        try this.externalReadAddress(chainId, "Merkl.AngleLabs") returns (address safe) {
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
