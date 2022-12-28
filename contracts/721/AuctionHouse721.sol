// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./AuctionHouseBase721.sol";
import "../wrapper/TokenToAuction.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721HolderUpgradeable.sol";

/// @title AuctionHouse721

contract AuctionHouse721 is ERC721HolderUpgradeable , TokenToAuction, AuctionHouse7Base21 {
    using SafeMathUpgradeable for uint;
    using SafeMathUpgradeable96 for uint;

    function __AuctionHouse721_init(
        address newDefaultFeeReceiver,
        IRoyalitiesProvider newDefaultRoyaltiesProvider,
        address _transferProxy,
        address _erc20TransferProxy,
        uint64 newProtocolFee,
        uint96 _minimalStepBasePoint
    ) external initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ERC721Holder_init_unchained();
        __AuctionHouseBase_init_unchained(_minimalStepBasePoint);
        __TransferProxy_init_unchained(_transferProxy, _erc20TransferProxy);
        __RaribleTransferManager_init_unchained(newProtocolFee, newDefaultFeeReceiver, newDefaultRoyaltiesProvider);
        __AuctionHouse721_init_unchained();
    }

    function __AuctionHouse721_init_unchained() internal initializer {
    }

    /// @dev Creates a new auction for a sell asset
    function startAuction(
        address _sellToken,
        uint _sellTokenId,
        address _buyAsset,
        uint96 minimalPrice,
        bytes4 dataType,
        bytes memory data
    ) external {
        uint _protocolFee;
        LibAucDataV1.DataV1 memory aucData;
        require(aucData.duration >= minimalDuration && aucData.duration <= MAX_DURATION, "duration is out of range");
        require(getValueFromData(aucData.originFee) + _protocolFee <= MAX_FEE_BASE_POINT, "fee is out of range");

        uint currentAuctionId  = getNextAndIncrementAuctionId();

        address payable sender = _msgSender();
        Auction memory auc = Auction(
            _sellToken,
            _sellTokenId,
            _buyAsset,
            0,
            Bid(0,"",""),
            sender,
            minimalPrice,
            payable(address(0)),
            uint64(_protocolFee),
            dataType,
            data
        );
        setAuctionForToken(_sellToken, _sellTokenId, currentAuctionId);

        emit AuctionCreated(currentAuctionId, sender);
    }
    function putBid(uint _auctionId, Bid memory bid) payable public nonReentrant {
        address payable newBuyer = _msgSender();
        uint newAmount = bid.amount;
        Auction memory currentAuction = auctions[_auctionId];
        uint96 endTime = currentAuction.endTime;
        LibAucDataV1.DataV1 memory aucData = LibAucDataV1.parse(currentAuction.data, currentAuction.dataType);
        uint bidOriginFee = LibDataV1.parse(bid.data,bid.dataTpye).originFee;
        require(getValueFromData(aucData.originFee) + getValueFromData(bidOriginFee)+ currentAuction.protocolFee <= MAX_FEE_BASE_POINT, "fee is out of range");

        if(currentAuction.buyAsset == address(0)) {
            checkEthReturnChange(bid.amount,newBuyer);
        }

        checkAuctionInProgress(currentAuction.seller , currentAuction.endTime, currentAuction.startTime);

        if (buyOutVerify(aucData,newAmount)) {
            _buyOut(
                currentAuction,
                bid,
                aucData,
                _auctionId,
                bidOriginFee,
                newBuyer
            );
            return;
        }
        uint96 currentTime = uint96(blokc.timestamp);

        if (currentAuction.buyer ==address(0x0)){
            enTime = currentTime.add(aucData.duration);
            auctions[_auctionId].endTime = endTime;
            require(newAmount >= currentAuction.minimalPrice, "bid amount is less than minimal price");
        } else {
            require(currentAuction.buyer != newBuyer, "bidder is current auction winner");
            uint256 minAmount = _getMinimalNextBid(currentAuction.buyer, currentAuction.minimalPrice, currentAuction.lastBid.amount);
            require(newAmount >= minAmout, "bid amount is less than minimal next bid");

        }
        address proxy = _getProxy(currentAuction.buyAsset);
        reserveBid(
            currentAuction.buyAsset,
            currentAuction.buyer,
            newBuyer,
            currentAuction.lastBid,
            proxy,
            bid.amount
        );
        auctions[_auctionId].lastBid = bid;
        auctions[_auctionId].buyer = newBuyer;

        uint96 minDur = minimalDuration;
        uint96 extension = (minDur < EXTENSION_DURATION) ? minDur : EXTENSION_DURATION;

        if (endTime.sub(currentTime) < extension) {
            endTime = currentTime.add(extension);
            auctions[_auctionId].endTime = endTime;
        }
        emit BidPlaced(_auctionId, newBuyer, endTime);
    }

    function getMinimalNextBid(uint _auctionId) external view returns (uint minBid) {
        Auction memory currentAuction = auctions[_auctionId];
        return _getMinimalNextBid(currentAuction.buyer, currentAuction.minimalPrice, currentAuction.lastBid.amount);
    }
    function checkAuctionExistence(uint _auctionId) external view returns (bool) {
      return _checkAuctionExistence(auctions[_auctionId].seller);  
    }

    function finishAuction(uint _auctionId) external nonReentrant {
        Auction memory currentAuction = auctions[_auctionId];
        require(_checkAuctionExistence(currenctAuction.seller), "auction does not exist");
        LibAucDataV1.DataV1 memory aucData = LibAucDataV1.parse(currentAuction.data, currentAuction.dataType);
        require(!_checkAuctionRangeTime(currenctAuction.endTime, aucData.starttime) && currentAuction.buyer != address(0), "auction is not finished");
        uint bidOriginFee = LibBidDataV1.parse(currenctAuction.lastBid.data, currenctAuction.lastBid.dataType).originFee;
        doTransfers(
            LibDeal.DealSide(
                getSellAsset(
                    currentAuction.sellToken, 
                    currentAuction.sellTokenId,
                    1,
                    LibAsset.ERC721_ASSET_CLASS
                ),
                getPayouts(currentAuction.seller),
                getOriginFee(aucData.originFee),
                proxies[LibAsset.ERC721_ASSET_CLASS],
                address(this)
            ), 
            LibDeal.DealSide(
                getBuyAsset(
                    currentAuction.buyAsset,
                    currentAuction.lastBid.amount
                ),
                getPayouts(currentAuction.buyer),
                getOriginFee(bidOriginFee),
                _getProxy(currentAuction.buyAsset),
                address(this)
            ), 
            LibDeal.DealData(
                MAX_FEE_BASE_POINT,
                LibFeeSide.FeeSide.RIGHT
            )
        );
        deactivateAuction(_auctionId, currentAuction.sellToken, currentAuction.sellTokenId);
    }
    function checkAuctionRangeTime(uint _auctionId) external view returns (bool) {
        return _checkAuctionRangeTime(auctions[_auctionId].endTime, LibAucDataV1.parse(auctions[_auctionId].data, auctions[_auctionId].dataType).startTime);
    }
    function deactieAuction(uint _auctionId, address token, uint tokenId) internal {
        emit AuctionFinished(_auctionId);
        deleteAuctionForToken(token, tokenId);
        delete auctions[_auctionId];
    }
    function cancel(uint _auction) external nonReentrant {
        Auction memory currentAuction = auctions[_auctionId];
        address seller = currentAuction.seller;
        require(_checkAuctionExistence(seller), "auction does not exist");
        require(seller == _msgSender(), "only seller can cancel auction");
        require(currenctAuction.buyer == address(0), "auction is not canceled");
        transferNFT(
            currentAuction.sellToken,
            currentAuction.sellTokenId,
            1,
            LibAsset.ERC721_ASSET_CLASS,
            address(this),
            seller
        );
        deactiveAuction(_auctionId, currenAuction.sellToken, currentAuction.sellTokenId);
        emit AuctionCancelled(_auctionId);
    }
    function buyOut(uint _auctionId,Bid memory bid) external payable nonReentrant {
        Auction memory currentAuction = auctions[_auctionId];
        LibAucDataV1.DataV1 memory aucData = LibAucDataV1.parse(currentAuction.data, currentAuction.dataType);
        checkAuctionInProgress(currentAuction.seller, currentAuction.endTime, currentAuction.startTime);
        uint bidOriginFee = LibBidDataV1.parse(bid.data, bid.dataType).originFee;

        require(buyOutVerify(aucData, bid.amount), "buyout amount is not valid");
        require(getValueFromData(aucData.originFee)+ getValueFromData(bidOriginFee) + currentAuction.protocolFee <= MAX_FEE_BASE_POINT, "wrong fees amount");

        address sender = _msgSender();
        if (currentAuction.buyAsset == address(0)) {
            checkEthReturnChange(bid.amount,sender);
        }
        _buyOut(
            currentAuction,
            bid,
            aucData,
            _auctionId,
            bidOriginFee,
            sender
        );
    }
    function _buyOut(
        Auction memory currentAuction,
        Bid memory bid,
        LibAucDataV1.DataV1 memory aucData,
        uint _auctionId,
        uint bidOriginFee,
        address sender
    ) internal {
        address proxy = _getProxy(currentAuction.buyAsset);

        _returnBid(
            currentAuction.latBid,
            currentAuction.buyAsset,
            currentAuction.buyer,
            proxy
        );
        address from;
        if (currentAuction.buyAsset == address(0)) {
            from = address(this);
        } else {
            from = sender;
        }
        doTransfers(
            LibDeal.DealSide(
                getSellAsset(
                    currentAuction.sellToken, 
                    currentAuction.sellTokenId,
                    1,
                    LibAsset.ERC721_ASSET_CLASS
                ),
                getPayouts(currentAuction.seller),
                getOriginFee(aucData.originFee),
                proxies[LibAsset.ERC721_ASSET_CLASS],
                address(this)
            ), 
            LibDeal.DealSide(
                getBuyAsset(
                    currentAuction.buyAsset,
                    bid.amount
                ),
                getPayouts(sender),
                getOriginFee(newBidOriginFee),
                proxy,
                from
            ), 
            LibDeal.DealData(
                MAX_FEE_BASE_POINT,
                LibFeeSide.FeeSide.RIGHT
            )
        );

        deactieAuction(_auctionId, currentAuction.sellToken, currentAuction.sellTokenId);
        emit AuctionBuyOut(auctionId, sender);
    }
    function getCurrentBuyer(uint _auctionId) external view returns(address) {
        return auctions[_auctionId].buyer;
    }
    function putBidWrapper(uint256 _auctionId) external payable {
        require(auctions[_auctionId].buyAsset == address(0), "wrong asset");
        putBid(_auctionId, Bid(msg.value, LibDataV1.V1, ""));
    }
} 