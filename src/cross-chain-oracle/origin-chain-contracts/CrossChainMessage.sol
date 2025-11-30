// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library CrossChainMessage {
    struct FeedMessage {
        bytes32 feedId;
        address sourceAggregator;
        uint64 sourceChainId;
        uint64 destinationChainId;
        address destinationFeed;
        uint8 decimals;
        string description;
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        bytes32 domainSeparator;
        uint256 timestamp;
    }

    function prepare(
        bytes32 feedId,
        address sourceAggregator,
        uint64 sourceChainId,
        uint64 destinationChainId,
        address destinationFeed,
        uint8 decimals,
        string memory description,
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound,
        bytes32 domainSeparator
    ) internal view returns (FeedMessage memory) {
        return FeedMessage({
            feedId: feedId,
            sourceAggregator: sourceAggregator,
            sourceChainId: sourceChainId,
            destinationChainId: destinationChainId,
            destinationFeed: destinationFeed,
            decimals: decimals,
            description: description,
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound,
            domainSeparator: domainSeparator,
            timestamp: block.timestamp
        });
    }

    function encode(FeedMessage memory message) internal pure returns (bytes memory) {
        return abi.encode(
            message.feedId,
            message.sourceAggregator,
            message.sourceChainId,
            message.destinationChainId,
            message.destinationFeed,
            message.decimals,
            message.description,
            message.roundId,
            message.answer,
            message.startedAt,
            message.updatedAt,
            message.answeredInRound,
            message.domainSeparator,
            message.timestamp
        );
    }

    function decode(bytes memory data) internal pure returns (FeedMessage memory) {
        (
            bytes32 feedId,
            address sourceAggregator,
            uint64 sourceChainId,
            uint64 destinationChainId,
            address destinationFeed,
            uint8 decimals,
            string memory description,
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound,
            bytes32 domainSeparator,
            uint256 timestamp
        ) = abi.decode(
            data,
            (bytes32, address, uint64, uint64, address, uint8, string, uint80, int256, uint256, uint256, uint80, bytes32, uint256)
        );

        return FeedMessage({
            feedId: feedId,
            sourceAggregator: sourceAggregator,
            sourceChainId: sourceChainId,
            destinationChainId: destinationChainId,
            destinationFeed: destinationFeed,
            decimals: decimals,
            description: description,
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound,
            domainSeparator: domainSeparator,
            timestamp: timestamp
        });
    }

    function hash(FeedMessage memory message) internal pure returns (bytes32) {
        return keccak256(encode(message));
    }

    function validate(FeedMessage memory message) internal view returns (bool) {
        if (message.feedId == bytes32(0)) return false;
        if (message.sourceAggregator == address(0)) return false;
        if (message.destinationFeed == address(0)) return false;
        if (message.roundId == 0) return false;
        if (message.answer <= 0) return false;
        if (message.updatedAt == 0) return false;
        if (message.updatedAt < message.startedAt) return false;
        if (message.timestamp > block.timestamp + 300) return false;
        return true;
    }
}