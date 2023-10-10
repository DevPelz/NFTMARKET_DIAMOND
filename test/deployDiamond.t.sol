// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "../contracts/Diamond.sol";
import "./helpers/DiamondUtils.sol";
import "./helpers/SigUtils.sol";
import {ERC721TOKEN} from "../contracts/facets/NFTFacet.sol";
import {NftMarketplace} from "../contracts/facets/NftMarketFacet.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";


contract DiamondDeployer is Helpers, DiamondUtils, IDiamondCut {
      using ECDSA for bytes32;
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    ERC721TOKEN nft;
    NftMarketplace nftMarket;
// NFT variables
uint256 ownerPriv =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public user = vm.addr(123444);
    // address public nftAddr;
    uint256 public tokenId = 9351;
    uint256 public price = 3 ether;
    uint256 public deadline = 1 days;
    bytes public signature;
    function setUp() public {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet), "Test", "TST");
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        nft = new ERC721TOKEN();
        nftMarket = new NftMarketplace();

        //upgrade diamond with facets

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](4);

        cut[0] = (
            FacetCut({
                facetAddress: address(dLoupe),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("DiamondLoupeFacet")
            })
        );

        cut[1] = (
            FacetCut({
                facetAddress: address(ownerF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("OwnershipFacet")
            })
        );

        cut[2] = (
            FacetCut({
                facetAddress: address(nft),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("ERC721TOKEN")
            })
        );

        cut[3] = (
            FacetCut({
                facetAddress: address(nftMarket),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("NftMarketplace")
            })
        );

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        //call a function
        DiamondLoupeFacet(address(diamond)).facetAddresses();

           signature = constructSig(
            nftAddr,
            tokenId,
            price,
            deadline,
            owner,
            ownerPriv
        );

        listing = Listing({
            nftAddress: nftAddr,
            tokenId: tokenId,
            price: price,
            seller: owner,
            deadline: deadline,
            status: true,
            signature: signature
        });

        address(nft).mint(owner, tokenId);
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}



    function testValidSig() public {
        vm.prank(owner);
        bytes memory sig = constructSig(
            listing.nftAddress,
            listing.tokenId,
            listing.price,
            listing.deadline,
            listing.seller,
            ownerPriv
        );
        listing.signature = sig;
        assertEq(sig, signature);
    }

    function testNotOwner() public {
        vm.startPrank(owner);
        Nft.mint(owner, 444);
        vm.stopPrank();
        vm.startPrank(user);
        vm.expectRevert(NftMarketplace.NotOwner.selector);
        NftMarket.listItem(listing);
        vm.stopPrank();
    }

    function testNotApproved() public {
        vm.startPrank(owner);
        Nft.mint(owner, 444);
        vm.expectRevert(NftMarketplace.NotApprovedForMarketplace.selector);
        NftMarket.listItem(listing);
        vm.stopPrank();
    }

    function testFailPrice() public {
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        listing.price = 0;
        // listing.status = false;
        vm.expectRevert(NftMarketplace.PriceMustBeAboveZero.selector);
        NftMarket.listItem(listing);
        assertEq(listing.status, false);
    }

    function testfailDeadline() public {
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        listing.deadline = 2 minutes;
        vm.expectRevert(NftMarketplace.MinDurationNotMet.selector);
        NftMarket.listItem(listing);
    }

    function testList() public {
        vm.startPrank(owner);
        Nft.mint(owner, 444);
        Nft.setApprovalForAll(address(NftMarket), true);
        listing.tokenId = 444;
        listing.price = 3 ether;
        listing.seller = owner;
        bytes memory sig = constructSig(
            listing.nftAddress,
            listing.tokenId,
            listing.price,
            listing.deadline,
            listing.seller,
            ownerPriv
        );
        listing.signature = sig;
        NftMarket.listItem(listing);

        assertEq(listing.price, price);
        assertEq(listing.tokenId, 444);
        assertEq(listing.deadline, deadline);
        assertEq(listing.seller, owner);
        assertEq(listing.signature, sig);
        assertTrue(listing.status);
        vm.stopPrank();
    }

    function testListFailIfNotOwner() public {
        vm.startPrank(user);
        listing.seller = user;
        vm.expectRevert(NftMarketplace.NotOwner.selector);
        NftMarket.listItem(listing);
        assertEq(listing.price, 3 ether);
        assertEq(listing.deadline, deadline);
        assertEq(listing.seller, user);
        assertEq(listing.signature, signature);
        vm.stopPrank();
    }

    function testBuy() public {
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        uint id = NftMarket.listItem(listing);
        vm.stopPrank();

        hoax(user, 20 ether);
        NftMarket.buyItem{value: 3 ether}(id);
        assertEq(Nft.ownerOf(tokenId), user);
    }

    function testBuyShouldRevertIfNotListed() public {
        vm.expectRevert(
            abi.encodeWithSelector(NftMarketplace.NotListed.selector, 3)
        );
        NftMarket.buyItem(3);
    }

    function testBuyShouldRevertIfPriceNotMet() public {
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        uint id = NftMarket.listItem(listing);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                NftMarketplace.PriceNotMet.selector,
                listing.price
            )
        );
        NftMarket.buyItem(id);
    }

    function testBuyItemFailIfExpired() public{
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        uint id = NftMarket.listItem(listing);
        vm.stopPrank();

        vm.prank(user);
        vm.warp(2 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NftMarketplace.Expired.selector,
                listing.deadline
            )
        );
        NftMarket.buyItem(id);
    }

    function testUpdateListing() public {
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        uint256 id = NftMarket.listItem(listing);

        NftMarket.updateListing(id, 3 ether, true);
        assertEq(listing.price, 3 ether);
        assertEq(listing.status, true);

        vm.stopPrank();
    }

    function testUpdateListingFailIfOrderIdIsGreater() public {
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        uint256 id = NftMarket.listItem(listing);

        vm.expectRevert(abi.encodeWithSelector(NftMarketplace.NotListed.selector, id + 1));
        NftMarket.updateListing(id + 1, 3 ether, true);
    }

    function testUpdateListingFailIfNotOwner() public {
        vm.startPrank(owner);
        Nft.setApprovalForAll(address(NftMarket), true);
        uint256 id = NftMarket.listItem(listing);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(NftMarketplace.NotOwner.selector);
        NftMarket.updateListing(id, 3 ether, true);
    }
}
}
