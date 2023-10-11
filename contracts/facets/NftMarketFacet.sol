// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {Sign} from "../libraries/signature.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract NftMarketplace {
    using ECDSA for bytes32;

    error PriceNotMet(uint256 price);
    error NotListed(uint256 listId);
    error Expired(uint256 deadline);
    error NotApprovedForMarketplace();
    error PriceMustBeAboveZero();
    error NotOwner();
    error MinDurationNotMet();
    error InvalidSignature();

    modifier isListed(uint256 listId) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.isActiveListing[listId] == false) {
            revert NotListed(listId);
        }
        _;
    }

    modifier isExpired(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert Expired(deadline);
        }
        _;
    }

    function listItem(
        LibDiamond.Listing calldata order
    ) external returns (uint256 id) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        uint256 orderId = ds.listCount;
        LibDiamond.Listing storage s = LibDiamond.diamondStorage().idToListing[
            orderId
        ];
        if (msg.sender != IERC721(order.nftAddress).ownerOf(order.tokenId)) {
            revert NotOwner();
        }
        if (
            !IERC721(order.nftAddress).isApprovedForAll(
                msg.sender,
                address(this)
            )
        ) {
            revert NotApprovedForMarketplace();
        }
        if (order.deadline - block.timestamp < 1 hours) {
            revert MinDurationNotMet();
        }
        if (order.price <= 0 ether) {
            revert PriceMustBeAboveZero();
        }

        bytes32 messageHash = Sign.constructMessageHash(
            order.nftAddress,
            order.tokenId,
            order.price,
            order.deadline,
            msg.sender
        );
        if (!Sign.isValid(messageHash, order.signature, msg.sender))
            revert InvalidSignature();

        s.nftAddress = order.nftAddress;
        s.tokenId = order.tokenId;
        s.price = order.price;
        s.seller = msg.sender;
        s.deadline = order.deadline;
        s.signature = order.signature;
        s.status = true;
        ds.isActiveListing[orderId] = true;
        id = ds.listCount;
        ds.listCount++;
        id;
    }

    function buyItem(
        uint256 orderId
    )
        external
        payable
        isListed(orderId)
        isExpired(LibDiamond.diamondStorage().idToListing[orderId].deadline)
    {
        LibDiamond.Listing storage s = LibDiamond.diamondStorage().idToListing[
            orderId
        ];

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (ds.isActiveListing[orderId] == false) {
            revert NotListed(orderId);
        }
        if (msg.value != s.price) {
            revert PriceNotMet(s.price);
        }
        ds.isActiveListing[orderId] = false;

        payable(s.seller).transfer(s.price);
        IERC721(s.nftAddress).safeTransferFrom(s.seller, msg.sender, s.tokenId);
    }

    function updateListing(uint orderId, uint _price, bool status) external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (orderId > ds.listCount) {
            revert NotListed(orderId);
        }
        if (ds.isActiveListing[orderId] == false) {
            revert NotListed(orderId);
        }
        if (ds.idToListing[orderId].seller != msg.sender) {
            revert NotOwner();
        }

        LibDiamond.Listing storage s = LibDiamond.diamondStorage().idToListing[
            orderId
        ];
        s.price = _price;
        s.status = status;
        ds.isActiveListing[orderId] = status;
    }
}
