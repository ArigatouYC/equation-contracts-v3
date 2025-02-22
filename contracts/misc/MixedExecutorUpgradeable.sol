// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.23;

import "../types/PackedValue.sol";
import "../core/MarketIndexer.sol";
import "../plugins/RouterUpgradeable.sol";
import "../plugins/interfaces/IOrderBook.sol";
import "../plugins/interfaces/ILiquidator.sol";
import "../plugins/interfaces/IPositionRouter.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

/// @notice MixedExecutor is a contract that executes multiple calls in a single transaction
contract MixedExecutorUpgradeable is Multicall, GovernableUpgradeable {
    RouterUpgradeable public router;
    /// @notice The address of market indexer
    MarketIndexer public marketIndexer;
    /// @notice The address of liquidator
    ILiquidator public liquidator;
    /// @notice The address of position router
    IPositionRouter public positionRouter;
    /// @notice The address of price feed
    IPriceFeed public priceFeed;
    /// @notice The address of order book
    IOrderBook public orderBook;
    /// @notice The address of market manager
    IMarketManager public marketManager;

    /// @notice The executors
    mapping(address => bool) public executors;
    /// @notice Default receiving address of fee
    address payable public feeReceiver;
    /// @notice Indicates whether to cancel the order when an execution error occurs
    bool public cancelOrderIfFailedStatus;

    /// @notice Emitted when an executor is updated
    /// @param executor The address of executor to update
    /// @param active Updated status
    event ExecutorUpdated(address indexed executor, bool indexed active);

    /// @notice Emitted when the increase order execute failed
    /// @dev The event is only emitted when the execution error is caused
    /// by the `IOrderBook.InvalidMarketPriceToTrigger`
    /// @param orderIndex The index of order to execute
    event IncreaseOrderExecuteFailed(uint256 indexed orderIndex);
    /// @notice Emitted when the increase order cancel succeeded
    /// @dev The event is emitted when the cancel order is successful after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason The shortened reason of the execution error
    event IncreaseOrderCancelSucceeded(uint256 indexed orderIndex, bytes4 shortenedReason);
    /// @notice Emitted when the increase order cancel failed
    /// @dev The event is emitted when the cancel order is failed after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason1 The shortened reason of the execution error
    /// @param shortenedReason2 The shortened reason of the cancel error
    event IncreaseOrderCancelFailed(uint256 indexed orderIndex, bytes4 shortenedReason1, bytes4 shortenedReason2);

    /// @notice Emitted when the decrease order execute failed
    /// @dev The event is only emitted when the execution error is caused
    /// by the `IOrderBook.InvalidMarketPriceToTrigger`
    /// @param orderIndex The index of order to execute
    event DecreaseOrderExecuteFailed(uint256 indexed orderIndex);
    /// @notice Emitted when the decrease order cancel succeeded
    /// @dev The event is emitted when the cancel order is successful after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason The shortened reason of the execution error
    event DecreaseOrderCancelSucceeded(uint256 indexed orderIndex, bytes4 shortenedReason);
    /// @notice Emitted when the decrease order cancel failed
    /// @dev The event is emitted when the cancel order is failed after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason1 The shortened reason of the execution error
    /// @param shortenedReason2 The shortened reason of the cancel error
    event DecreaseOrderCancelFailed(uint256 indexed orderIndex, bytes4 shortenedReason1, bytes4 shortenedReason2);

    /// @notice Emitted when the liquidity position liquidate failed
    /// @dev The event is emitted when the liquidate is failed after the execution error
    /// @param market The address of market
    /// @param account The owner of the position
    /// @param shortenedReason The shortened reason of the execution error
    event LiquidateLiquidityPositionFailed(IMarketDescriptor indexed market, address account, bytes4 shortenedReason);
    /// @notice Emitted when the position liquidate failed
    /// @dev The event is emitted when the liquidate is failed after the execution error
    /// @param market The address of market
    /// @param account The address of account
    /// @param side The side of position to liquidate
    /// @param shortenedReason The shortened reason of the execution error
    event LiquidatePositionFailed(
        IMarketDescriptor indexed market,
        address indexed account,
        Side indexed side,
        bytes4 shortenedReason
    );

    /// @notice Error thrown when the execution error and `requireSuccess` is set to true
    error ExecutionFailed(bytes reason);

    modifier onlyExecutor() {
        if (!executors[msg.sender]) revert Forbidden();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        RouterUpgradeable _router,
        MarketIndexer _marketIndexer,
        ILiquidator _liquidator,
        IPositionRouter _positionRouter,
        IPriceFeed _priceFeed,
        IOrderBook _orderBook,
        IMarketManager _marketManager
    ) public initializer {
        __Governable_init();

        (router, marketIndexer, liquidator, positionRouter) = (_router, _marketIndexer, _liquidator, _positionRouter);
        (priceFeed, orderBook, marketManager) = (_priceFeed, _orderBook, _marketManager);
        cancelOrderIfFailedStatus = true;
    }

    /// @notice Set executor status active or not
    /// @param _executor Executor address
    /// @param _active Status of executor permission to set
    function setExecutor(address _executor, bool _active) external virtual onlyGov {
        executors[_executor] = _active;
        emit ExecutorUpdated(_executor, _active);
    }

    /// @notice Set fee receiver
    /// @param _receiver The address of new fee receiver
    function setFeeReceiver(address payable _receiver) external virtual onlyGov {
        feeReceiver = _receiver;
    }

    /// @notice Set whether to cancel the order when an execution error occurs
    /// @param _cancelOrderIfFailedStatus If the _cancelOrderIfFailedStatus is set to 1, the order is canceled
    /// when an error occurs
    function setCancelOrderIfFailedStatus(bool _cancelOrderIfFailedStatus) external virtual onlyGov {
        cancelOrderIfFailedStatus = _cancelOrderIfFailedStatus;
    }

    /// @notice Update prices
    /// @param _packedValues The packed values of the market index and priceX96: bit 0-23 represent the market, and
    /// bit 24-183 represent the priceX96
    /// @param _timestamp The timestamp of the price update
    function setPriceX96s(PackedValue[] calldata _packedValues, uint64 _timestamp) external virtual onlyExecutor {
        IPriceFeed.MarketPrice[] memory marketPrices = new IPriceFeed.MarketPrice[](_packedValues.length);
        uint256 len = _packedValues.length;
        for (uint256 i; i < len; ++i) {
            marketPrices[i] = IPriceFeed.MarketPrice({
                market: marketIndexer.indexMarkets(_packedValues[i].unpackUint24(0)),
                priceX96: _packedValues[i].unpackUint160(24)
            });
        }
        priceFeed.setPriceX96s(marketPrices, _timestamp);
    }

    /// @notice Execute multiple increase liquidity position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeIncreaseLiquidityPositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeIncreaseLiquidityPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple decrease liquidity position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeDecreaseLiquidityPositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeDecreaseLiquidityPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple increase position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeIncreasePositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeIncreasePositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple decrease position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeDecreasePositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeDecreasePositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Settle funding fee batch
    /// @param _packedValue The packed values of the market index and packed markets count. The maximum packed markets
    /// count is 10: bit 0-23 represent the market index 1, bit 24-47 represent the market index 2, and so on, and bit
    /// 240-247 represent the packed markets count
    function settleFundingFeeBatch(PackedValue _packedValue) external virtual onlyExecutor {
        uint8 packedMarketsCount = _packedValue.unpackUint8(240);
        require(packedMarketsCount <= 10);
        for (uint8 i; i < packedMarketsCount; ++i) {
            unchecked {
                router.pluginSettleFundingFee(marketIndexer.indexMarkets(_packedValue.unpackUint24(i * 24)));
            }
        }
    }

    /// @notice Collect protocol fee batch
    /// @param _packedValue The packed values of the market index and packed markets count. The maximum packed markets
    /// count is 10: bit 0-23 represent the market index 1, bit 24-47 represent the market index 2, and so on, and bit
    /// 240-247 represent the packed markets count
    function collectProtocolFeeBatch(PackedValue _packedValue) external virtual onlyExecutor {
        uint8 packedMarketsCount = _packedValue.unpackUint8(240);
        require(packedMarketsCount <= 10);
        for (uint8 i; i < packedMarketsCount; ++i) {
            unchecked {
                marketManager.collectProtocolFee(marketIndexer.indexMarkets(_packedValue.unpackUint24(i * 24)));
            }
        }
    }

    /// @notice Execute an existing increase order
    /// @param _packedValue The packed values of the order index and require success flag: bit 0-247 represent
    /// the order index, and bit 248 represent the require success flag
    function executeIncreaseOrder(PackedValue _packedValue) external virtual onlyExecutor {
        address payable receiver = _getFeeReceiver();
        uint248 orderIndex = _packedValue.unpackUint248(0);
        bool requireSuccess = _packedValue.unpackBool(248);

        try orderBook.executeIncreaseOrder(orderIndex, receiver) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);

            // If the order cannot be triggered due to changes in the market price,
            // it is unnecessary to cancel the order
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            if (errorTypeSelector == IOrderBook.InvalidMarketPriceToTrigger.selector) {
                emit IncreaseOrderExecuteFailed(orderIndex);
                return;
            }

            if (cancelOrderIfFailedStatus) {
                try orderBook.cancelIncreaseOrder(orderIndex, receiver) {
                    emit IncreaseOrderCancelSucceeded(orderIndex, errorTypeSelector);
                } catch (bytes memory reason2) {
                    emit IncreaseOrderCancelFailed(orderIndex, errorTypeSelector, _decodeShortenedReason(reason2));
                }
            }
        }
    }

    /// @notice Execute an existing decrease order
    /// @param _packedValue The packed values of the order index and require success flag: bit 0-247 represent
    /// the order index, and bit 248 represent the require success flag
    function executeDecreaseOrder(PackedValue _packedValue) external virtual onlyExecutor {
        address payable receiver = _getFeeReceiver();
        uint248 orderIndex = _packedValue.unpackUint248(0);
        bool requireSuccess = _packedValue.unpackBool(248);

        try orderBook.executeDecreaseOrder(orderIndex, receiver) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);

            // If the order cannot be triggered due to changes in the market price,
            // it is unnecessary to cancel the order
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            if (errorTypeSelector == IOrderBook.InvalidMarketPriceToTrigger.selector) {
                emit DecreaseOrderExecuteFailed(orderIndex);
                return;
            }

            if (cancelOrderIfFailedStatus) {
                try orderBook.cancelDecreaseOrder(orderIndex, receiver) {
                    emit DecreaseOrderCancelSucceeded(orderIndex, errorTypeSelector);
                } catch (bytes memory reason2) {
                    emit DecreaseOrderCancelFailed(orderIndex, errorTypeSelector, _decodeShortenedReason(reason2));
                }
            }
        }
    }

    /// @notice Liquidate a liquidity position
    /// @param _packedValue The packed values of the market index, position id, and require success flag:
    /// bit 0-23 represent the market index, bit 24-183 represent the account, and bit 184 represent the
    /// require success flag
    function liquidateLiquidityPosition(PackedValue _packedValue) external virtual onlyExecutor {
        IMarketDescriptor market = marketIndexer.indexMarkets(_packedValue.unpackUint24(0));
        address account = _packedValue.unpackAddress(24);
        bool requireSuccess = _packedValue.unpackBool(184);

        try liquidator.liquidateLiquidityPosition(market, account, _getFeeReceiver()) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);
            emit LiquidateLiquidityPositionFailed(market, account, _decodeShortenedReason(reason));
        }
    }

    /// @notice Liquidate a position
    /// @param _packedValue The packed values of the market index, account, side, and require success flag:
    /// bit 0-23 represent the market index, bit 24-183 represent the account, bit 184-191 represent the side,
    /// and bit 192 represent the require success flag
    function liquidatePosition(PackedValue _packedValue) external virtual onlyExecutor {
        IMarketDescriptor market = marketIndexer.indexMarkets(_packedValue.unpackUint24(0));
        address account = _packedValue.unpackAddress(24);
        Side side = Side.wrap(_packedValue.unpackUint8(184));
        bool requireSuccess = _packedValue.unpackBool(192);

        try liquidator.liquidatePosition(market, account, side, _getFeeReceiver()) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);

            emit LiquidatePositionFailed(market, account, side, _decodeShortenedReason(reason));
        }
    }

    /// @notice Decode the shortened reason of the execution error
    /// @dev The default implementation is to return the first 4 bytes of the reason, which is typically the
    /// selector for the error type
    /// @param _reason The reason of the execution error
    /// @return The shortened reason of the execution error
    function _decodeShortenedReason(bytes memory _reason) internal pure virtual returns (bytes4) {
        return bytes4(_reason);
    }

    function _getFeeReceiver() internal view virtual returns (address payable) {
        return feeReceiver == address(0) ? payable(msg.sender) : feeReceiver;
    }
}
