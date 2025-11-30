// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "../../../lib/reactive-lib/src/interfaces/IReactive.sol";
import "../../../lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";

/**
 * @title ChainlinkFeedMirrorReactive
 * @notice Ultra-simplified reactive contract for mirroring Chainlink feeds
 * @dev CRON triggers FeedReader, then relays all CrossChainMessageReady events to destinations
 *      NO REGISTRATION NEEDED - Everything managed in FeedReader!
 */
contract ChainlinkFeedMirrorReactive is AbstractPausableReactive {
    
    // ============ Events ============
    
    event CronTriggered(
        uint256 indexed blockNumber,
        uint256 timestamp,
        address indexed feedReader
    );
    
    event PriceUpdateRelayed(
        bytes32 indexed feedId,
        address indexed destinationFeed,
        uint64 destinationChainId,
        uint80 roundId,
        int256 answer
    );
    
    event ProcessingError(
        string reason,
        bytes32 feedId
    );
    
    // ============ Constants ============
    
    // Event signature for CrossChainMessageReady from FeedReader
    // keccak256("CrossChainMessageReady(bytes32,address,uint64,address,uint8,string,uint80,int256,uint256,uint256,uint80,uint256)")
    uint256 private constant CROSS_CHAIN_MESSAGE_READY_TOPIC_0 = 0x98eacf08909732d882c28676505c67cea093bb9dea7c176b7e86c5c0a8c217ba;
    
    uint64 private constant CALLBACK_GAS_LIMIT = 1000000;
    
    // Cooldown to prevent duplicate processing of same round
    uint256 private constant UPDATE_COOLDOWN = 60; // 1 minute
    
    // ============ Structs ============
    
    struct PriceUpdateRecord {
        uint80 lastRoundId;
        int256 lastAnswer;
        uint256 lastUpdatedAt;
        uint256 lastProcessedAt;
    }
    
    // ============ State Variables ============
    address public immutable feedReader;
    uint64 public immutable originChainId;
    uint256 public immutable CRON_TOPIC;
    
    // Price update tracking (by feedId to prevent duplicates)
    mapping(bytes32 => PriceUpdateRecord) public priceRecords;
    
    // Track last cron execution
    uint256 public lastCronBlock;
    uint256 public lastCronTimestamp;
    uint256 public cronExecutionCount;
    
    // ============ Constructor ============
    
    /**
     * @param _owner Contract owner address
     * @param _feedReader Address of FeedReader contract on origin chain
     * @param _originChainId Chain ID of origin chain
     * @param _service Address of Reactive Network system contract
     * @param _cronTopic CRON topic to subscribe to
     */
    constructor(
        address _owner,
        address _feedReader,
        uint64 _originChainId,
        address _service,
        uint256 _cronTopic
    ) payable { 
        owner = _owner;
        feedReader = _feedReader;
        originChainId = _originChainId;
        service = ISystemContract(payable(_service));
        CRON_TOPIC = _cronTopic;
        
        if (!vm) {
            // Subscribe to CRON events
            service.subscribe(
                block.chainid,
                address(service),
                _cronTopic,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            
            // Subscribe to CrossChainMessageReady events from FeedReader
            service.subscribe(
                _originChainId,
                _feedReader,
                CROSS_CHAIN_MESSAGE_READY_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }
    
    // ============ AbstractPausableReactive Implementation ============
    
    /**
     * @notice Returns subscriptions that can be paused/resumed
     */
    function getPausableSubscriptions() internal view override returns (Subscription[] memory) {
        Subscription[] memory result = new Subscription[](2);
        
        // CRON subscription
        result[0] = Subscription(
            block.chainid,
            address(service),
            CRON_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        
        // CrossChainMessageReady subscription from FeedReader
        result[1] = Subscription(
            originChainId,
            feedReader,
            CROSS_CHAIN_MESSAGE_READY_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        
        return result;
    }
    
    // ============ Main Reaction Function ============
    
    /**
     * @notice Main reaction function - handles CRON and CrossChainMessageReady events
     * @param log The log record from the blockchain
     */
    function react(LogRecord calldata log) external vmOnly {
        if (log.topic_0 == CRON_TOPIC) {
            // CRON event - trigger FeedReader
            _handleCronEvent();
        } else if (log.topic_0 == CROSS_CHAIN_MESSAGE_READY_TOPIC_0 && 
                   log._contract == feedReader) {
            // CrossChainMessageReady from FeedReader - relay to destination
            _handleCrossChainMessage(log);
        }
    }
    
    // ============ CRON Event Handling ============
    
    /**
     * @notice Handle CRON event - trigger readAndEmitAll() on FeedReader
     */
    function _handleCronEvent() internal {
        lastCronBlock = block.number;
        lastCronTimestamp = block.timestamp;
        cronExecutionCount++;
        
        // Emit callback to FeedReader to read all feeds
        bytes memory payload = abi.encodeWithSignature("readAndEmitAll(address)", address(0));
        
        emit Callback(originChainId, feedReader, CALLBACK_GAS_LIMIT, payload);
        
        emit CronTriggered(block.number, block.timestamp, feedReader);
    }
    
    // ============ CrossChainMessage Event Handling ============
    
    /**
     * @notice Handle CrossChainMessageReady event from FeedReader
     * @dev Validates data and relays to destination chain
     */
    function _handleCrossChainMessage(LogRecord calldata log) internal {
        // Extract indexed parameters
        bytes32 feedId = bytes32(log.topic_1);
        address aggregator = address(uint160(uint256(log.topic_2)));
        
        // Decode non-indexed parameters
        (
            uint64 destinationChainId,
            address destinationFeed,
            uint8 decimals,
            string memory description,
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound,
            uint256 timestamp
        ) = abi.decode(
            log.data,
            (uint64, address, uint8, string, uint80, int256, uint256, uint256, uint80, uint256)
        );
        
        // Check cooldown to prevent duplicate processing
        PriceUpdateRecord storage record = priceRecords[feedId];
        if (record.lastRoundId == roundId && 
            block.timestamp < record.lastProcessedAt + UPDATE_COOLDOWN) {
            return; // Already processed recently
        }
        
        // Validate price data
        if (answer <= 0) {
            emit ProcessingError("Invalid price: non-positive answer", feedId);
            return;
        }
        
        if (roundId == 0) {
            emit ProcessingError("Invalid round ID", feedId);
            return;
        }
        
        if (updatedAt == 0 || updatedAt > block.timestamp + 300) {
            emit ProcessingError("Invalid timestamp", feedId);
            return;
        }
        
        if (destinationFeed == address(0)) {
            emit ProcessingError("Invalid destination proxy", feedId);
            return;
        }
        
        // Update price record
        record.lastRoundId = roundId;
        record.lastAnswer = answer;
        record.lastUpdatedAt = updatedAt;
        record.lastProcessedAt = block.timestamp;
        
        // Relay to destination
        _relayToDestination(
            destinationChainId,
            destinationFeed,
            feedId,
            roundId,
            answer,
            startedAt,
            updatedAt,
            answeredInRound
        );
    }
    
    /**
     * @notice Relay price update to destination chain
     */
    function _relayToDestination(
        uint64 destinationChainId,
        address destinationFeed,
        bytes32 feedId,
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal {
        // Create callback payload for FeedMirror.updatePrice()
        bytes memory payload = abi.encodeWithSignature(
            "updatePrice(address,uint80,int256,uint256,uint256,uint80)",
            address(0),
            roundId,
            answer,
            startedAt,
            updatedAt,
            answeredInRound
        );
        
        // Emit callback to destination chain
        emit Callback(destinationChainId, destinationFeed, CALLBACK_GAS_LIMIT, payload);
        
        emit PriceUpdateRelayed(feedId, destinationFeed, destinationChainId, roundId, answer);
    }
    
    // ============ Manual Trigger (Testing/Emergency) ============
    
    /**
     * @notice Manually trigger FeedReader (for testing/emergency)
     */
    function manualTrigger() external onlyOwner {
        bytes memory payload = abi.encodeWithSignature("readAndEmitAll(address)", address(0));
        emit Callback(originChainId, feedReader, CALLBACK_GAS_LIMIT, payload);
        emit CronTriggered(block.number, block.timestamp, feedReader);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get last price record for a feed
     */
    function getLastPriceRecord(bytes32 feedId) external view returns (
        uint80 lastRoundId,
        int256 lastAnswer,
        uint256 lastUpdatedAt,
        uint256 lastProcessedAt
    ) {
        PriceUpdateRecord storage record = priceRecords[feedId];
        return (
            record.lastRoundId,
            record.lastAnswer,
            record.lastUpdatedAt,
            record.lastProcessedAt
        );
    }
    
    /**
     * @notice Get last CRON execution info
     */
    function getLastCronInfo() external view returns (
        uint256 blockNumber,
        uint256 timestamp,
        uint256 executionCount
    ) {
        return (lastCronBlock, lastCronTimestamp, cronExecutionCount);
    }
    
    /**
     * @notice Get configuration
     */
    function getConfig() external view returns (
        address _feedReader,
        uint64 _originChainId,
        uint256 _cronTopic
    ) {
        return (feedReader, originChainId, CRON_TOPIC);
    }
    
    // ============ Emergency Functions ============
    
    /**
     * @notice Emergency withdrawal of ETH
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @notice Withdraw all ETH
     */
    function withdrawAllETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Transfer failed");
    }
}
