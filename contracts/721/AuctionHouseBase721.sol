// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "../AuctionHouseBase.sol";

abstract contract AuctionHouseBase721 is AuctionHouseBase {
    mapping (uint=>Auction) auctions;

    struct Acution {
        address sellToken;
        uint sellTokenId;
        address buyAsset;
        uint96 endTime;
        Bid lastBid;
        address payable seller;
        uint96 minimalPrice;
        address payable buyer;
        uint64 protocolFee;
        bytes4 dataType;
        bytes data;
    }
}