// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
contract TokenToAuction {

    mapping(address => mapping(uint256 => uint256)) private tokenToAuctionId;

    function getAuctionByToken(address _collection, uint tokenId) external view returns(uint) {
        return tokenToAuctionId[_collection][tokenId];
    }
    function setAuctionForToken(address token, uint tokenId, uint auctionId) internal {
        tokenToAuctionId[token][tokenId] = auctionId;
    }
    function deleteAuctionForToken(address token, uint tokenId) internal {
        delete tokenToAuctionId[token][tokenId];
    }
    uint256[50] private ______gap;
}