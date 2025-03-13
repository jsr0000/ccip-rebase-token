// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "lib/openzeppelin-contracts/lib/forge-std/src/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {IRebaseToken} from "src/Interfaces/IRebaseToken.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "lib/chainlink-local/lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "lib/chainlink-local/lib/ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 constant SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    Vault vault;
    RebaseTokenPool localPool;
    RebaseTokenPool remotePool;
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        address[] memory allowlist = new address[](0);
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // deploy and configure on sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        localPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(localPool));
        RegistryModuleOwnerCustom(
            sepoliaNetworkDetails.registryModuleOwnerCustomAddress
        ).registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(localPool));
        vm.stopPrank();

        // deploy and configure on arbitrum sepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );
        arbSepoliaToken = new RebaseToken();
        remotePool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(remotePool));
        RegistryModuleOwnerCustom(
            arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress
        ).registerAdminViaOwner(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(remotePool));
        vm.startPrank(owner);

        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        TokenPool LocalPool,
        TokenPool RemotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(RemotePool));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        LocalPool.applyChainUpdates(remoteChainSelectorsToRemove, chains);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // Create the message to send tokens cross-chain
        vm.selectFork(localFork);
        vm.startPrank(user);
        Client.EVMTokenAmount[]
            memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: address(localToken),
            amount: amountToBridge
        });
        tokenToSendDetails[0] = tokenAmount;
        // Approve the router to burn tokens on users behalf
        IERC20(address(localToken)).approve(
            localNetworkDetails.routerAddress,
            amountToBridge
        );

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: 500_000,
                    allowOutOfOrderExecution: false
                })
            ), // We don't need any extra args for this example
            feeToken: localNetworkDetails.linkAddress // The token used to pay for the fee
        });
        // Get and approve the fees
        vm.stopPrank();
        // Give the user the fee amount of LINK
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            user,
            IRouterClient(localNetworkDetails.routerAddress).getFee(
                remoteNetworkDetails.chainSelector,
                message
            )
        );
        vm.startPrank(user);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(
                remoteNetworkDetails.chainSelector,
                message
            )
        ); // Approve the fee
        // log the values before bridging
        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(
            user
        );
        console.log("Local balance before bridge: %d", balanceBeforeBridge);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(
            remoteNetworkDetails.chainSelector,
            message
        ); // Send the message
        uint256 sourceBalanceAfterBridge = IERC20(address(localToken))
            .balanceOf(user);
        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge);
        assertEq(
            sourceBalanceAfterBridge,
            balanceBeforeBridge - amountToBridge
        );
        vm.stopPrank();

        vm.selectFork(remoteFork);
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 15 minutes);
        // get initial balance on Arbitrum
        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(
            user
        );
        console.log("Remote balance before bridge: %d", initialArbBalance);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        console.log(
            "Remote user interest rate: %d",
            remoteToken.getUserInterestRate(user)
        );
        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(user);
        console.log("Remote balance after bridge: %d", destBalance);
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    function testBridgeAllTokens() public {
        configureTokenPool(
            sepoliaFork,
            TokenPool(address(localPool)),
            TokenPool(address(remotePool)),
            IRebaseToken(address(arbSepoliaToken)),
            arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork,
            TokenPool(address(remotePool)),
            TokenPool(address(localPool)),
            IRebaseToken(address(sepoliaToken)),
            sepoliaNetworkDetails
        );
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);
        bridgeTokens(
            arbSepoliaToken.balanceOf(user),
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
    }
}
