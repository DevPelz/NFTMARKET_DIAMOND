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
import {LibDiamond} from "../contracts/libraries/LibDiamond.sol";

contract DiamondDeployer is Helpers, DiamondUtils, IDiamondCut {
    using ECDSA for bytes32;
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    ERC721TOKEN nft;
    NftMarketplace nftMarket;
    NftMarketplace nftMarketDiamond;
    ERC721TOKEN nftDiamond;
    // NFT variables
    uint256 ownerPriv =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public user = vm.addr(123444);

    // struct definition
    LibDiamond.Listing listing;

    function setUp() public {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet), "Test", "TST");
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        nft = new ERC721TOKEN();
        nftMarket = new NftMarketplace();

        nftDiamond = ERC721TOKEN(address(diamond));
        nftMarketDiamond = NftMarketplace(address(diamond));

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
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}

    function testNotOwner() public {
        vm.startPrank(owner);
        nftDiamond.mint(owner, 444);
        vm.stopPrank();
        vm.startPrank(user);
        vm.expectRevert();

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;
        nftMarketDiamond.listItem(l);
        vm.stopPrank();
    }

    function testNotApproved() public {
        vm.startPrank(owner);
        nftDiamond.mint(owner, 444);
        vm.expectRevert();

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;
        nftMarketDiamond.listItem(l);
        vm.stopPrank();
    }

    function testInvalidPrice() public {
        vm.startPrank(owner);
        nftDiamond.setApprovalForAll(address(nftMarket), true);
        vm.expectRevert();

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 0;
        l.seller = owner;
        l.deadline = 2 hours;
        nftMarketDiamond.listItem(l);
        assertEq(listing.status, false);
    }

    function testfailDeadline() public {
        vm.startPrank(owner);
        nftDiamond.mint(owner, 444);
        nftDiamond.setApprovalForAll(address(nftMarketDiamond), true);

        vm.expectRevert();

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 minutes;

        nftMarketDiamond.listItem(l);
    }

    function testList() public {
        nftDiamond.mint(owner, 444);
        vm.startPrank(owner);
        nftDiamond.setApprovalForAll(address(diamond), true);

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;

        bytes memory sig = constructSig(
            l.nftAddress,
            l.tokenId,
            l.price,
            l.deadline,
            l.seller,
            ownerPriv
        );
        l.signature = sig;
        nftMarketDiamond.listItem(l);

        assertEq(l.price, 3 ether);
        assertEq(l.tokenId, 444);
        assertEq(l.seller, owner);
        assertEq(l.signature, sig);
        vm.stopPrank();
    }

    function testBuy() public {
        vm.startPrank(owner);
        nftDiamond.mint(owner, 444);
        nftDiamond.setApprovalForAll(address(diamond), true);

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;

        bytes memory sig = constructSig(
            l.nftAddress,
            l.tokenId,
            l.price,
            l.deadline,
            l.seller,
            ownerPriv
        );
        l.signature = sig;
        uint id = nftMarketDiamond.listItem(l);

        vm.stopPrank();

        // vm.startPrank(user);
        hoax(user, 20 ether);
        nftMarketDiamond.buyItem{value: 3 ether}(id);
        assertEq(nftDiamond.ownerOf(l.tokenId), user);
    }

    function testBuyShouldRevertIfNotListed() public {
        vm.expectRevert(
            abi.encodeWithSelector(NftMarketplace.NotListed.selector, 3)
        );
        nftMarketDiamond.buyItem(3);
    }

    function testBuyShouldRevertIfPriceNotMet() public {
        vm.startPrank(owner);

        nftDiamond.mint(owner, 444);
        nftDiamond.setApprovalForAll(address(diamond), true);

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;

        bytes memory sig = constructSig(
            l.nftAddress,
            l.tokenId,
            l.price,
            l.deadline,
            l.seller,
            ownerPriv
        );
        l.signature = sig;
        uint id = nftMarketDiamond.listItem(l);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(NftMarketplace.PriceNotMet.selector, l.price)
        );
        nftMarketDiamond.buyItem(id);
    }

    function testBuyItemFailIfExpired() public {
        nftDiamond.mint(owner, 444);
        vm.startPrank(owner);
        nftDiamond.setApprovalForAll(address(diamond), true);

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;

        bytes memory sig = constructSig(
            l.nftAddress,
            l.tokenId,
            l.price,
            l.deadline,
            l.seller,
            ownerPriv
        );
        l.signature = sig;
        uint id = nftMarketDiamond.listItem(l);

        vm.startPrank(user);
        vm.warp(2 days);
        vm.expectRevert(
            abi.encodeWithSelector(NftMarketplace.Expired.selector, l.deadline)
        );
        nftMarketDiamond.buyItem(id);
    }

    function testUpdateListing() public {
        nftDiamond.mint(owner, 444);
        vm.startPrank(owner);
        nftDiamond.setApprovalForAll(address(diamond), true);

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;

        bytes memory sig = constructSig(
            l.nftAddress,
            l.tokenId,
            l.price,
            l.deadline,
            l.seller,
            ownerPriv
        );
        l.signature = sig;
        uint id = nftMarketDiamond.listItem(l);

        nftMarketDiamond.updateListing(id, 3 ether, true);
        assertEq(l.price, 3 ether);

        vm.stopPrank();
    }

    function testUpdateListingFailIfOrderIdIsGreater() public {
        nftDiamond.mint(owner, 444);
        vm.startPrank(owner);
        nftDiamond.setApprovalForAll(address(diamond), true);

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;

        bytes memory sig = constructSig(
            l.nftAddress,
            l.tokenId,
            l.price,
            l.deadline,
            l.seller,
            ownerPriv
        );
        l.signature = sig;
        uint id = nftMarketDiamond.listItem(l);

        vm.expectRevert(
            abi.encodeWithSelector(NftMarketplace.NotListed.selector, id + 1)
        );
        nftMarketDiamond.updateListing(id + 1, 3 ether, true);
    }

    function testUpdateListingFailIfNotOwner() public {
        nftDiamond.mint(owner, 444);
        vm.startPrank(owner);
        nftDiamond.setApprovalForAll(address(diamond), true);

        LibDiamond.Listing memory l;
        l.nftAddress = address(nftDiamond);
        l.tokenId = 444;
        l.price = 3 ether;
        l.seller = owner;
        l.deadline = 2 hours;

        bytes memory sig = constructSig(
            l.nftAddress,
            l.tokenId,
            l.price,
            l.deadline,
            l.seller,
            ownerPriv
        );
        l.signature = sig;
        uint id = nftMarketDiamond.listItem(l);

        vm.startPrank(user);
        vm.expectRevert(NftMarketplace.NotOwner.selector);
        nftMarketDiamond.updateListing(id, 3 ether, true);
    }
}
