"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Reverse Auction
// Author: Nicholas Shellabarger
// Version: 0.4.2 - fix cancel, add seller addr
// Requires Reach v0.1.7
// -----------------------------------------------

const SERIAL_VER = 0;

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

const DIST_LENGTH = 10;

// FUNCS

/*
 * precision used in fixed point arithmetic
 */
const precision = 1000000; // 10 ^ 6

/*
 * calculate price based on seconds elapsed since reference secs
 */
const priceFunc = (startPrice, floorPrice, referenceConcensusSecs, dk) =>
  max(
    floorPrice,
    ((diff) => (startPrice <= diff ? floorPrice : startPrice - diff))(
      min(
        ((lastConsensusSecs() - referenceConcensusSecs) * dk) / precision,
        startPrice - floorPrice
      )
    )
  );

/*
 * caculate percent
 * c - cap
 * i - part
 * p - precision
 */
const percent = (c, i, p) => {
  const fD = fx(6)(Pos, i);
  const fD2 = fx(6)(Pos, c);
  return fxdiv(fD, fD2, p);
};

/*
 * calulate payout
 * amt - amount to split
 * d - distribution [0,10000]
 */
const payout = (rc, amt, d) =>
  fxmul(fx(6)(Pos, amt), percent(rc, d, precision)).i.i / precision;

// calculate slope
const calc = (d, d2, p) => {
  const fD = fx(6)(Pos, d);
  const fD2 = fx(6)(Pos, d2);
  return fxdiv(fD, fD2, p);
};

// INTERACTS

const relayInteract = {};

const auctioneerInteract = {
  getParams: Fun(
    [],
    Object({
      tokenAmount: UInt, // NFT token amount
      rewardAmount: UInt, // 1 ALGO
      startPrice: UInt, // 100
      floorPrice: UInt, // 1
      endSecs: UInt, // 1
      // -----------------------------------------
      // Royalties
      // -----------------------------------------
      //addrs: Array(Address, DIST_LENGTH),
      //distr: Array(UInt, DIST_LENGTH),
      //royaltyCap: UInt,
      // -----------------------------------------
    })
  ),
  signal: Fun([], Null),
};

export const Event = () => [];

export const Participants = () => [
  Participant("Auctioneer", auctioneerInteract),
  ParticipantClass("Relay", relayInteract),
];

export const Views = () => [
  View({
    manager: Address, // Standard View: Manager Address
    token: Token, // Asset Token
    tokenP: Token, // Payment Token
    currentPrice: UInt, // Current Price
    startPrice: UInt, // Start Price
    floorPrice: UInt, // Floor Price
    closed: Bool, // Closed
    endSecs: UInt, // End Seconds
    priceChangePerSec: UInt, // Price Change Per Second
  }),
];

export const Api = () => [
  API({
    touch: Fun([], Null), // Touch
    acceptOffer: Fun([], Null), // Accept Offer
    cancel: Fun([], Null), // Cancel
  }),
];

export const App = (map) => {
  const [
    { amt, ttl, tok0: token, tok1: tokenP },
    [addr, _],
    [Auctioneer, Relay],
    [v],
    [a],
    _,
  ] = map;
  Auctioneer.only(() => {
    const {
      tokenAmount,
      rewardAmount,
      startPrice,
      floorPrice,
      endSecs,
      // -----------------------------------------
      // Royalties
      // -----------------------------------------
      //addrs,
      //distr,
      //royaltyCap,
      // -----------------------------------------
    } = declassify(interact.getParams());
    assume(tokenAmount > 0);
    assume(rewardAmount > 0);
    assume(floorPrice > 0);
    assume(floorPrice <= startPrice); // fp < sp => auction, fp == sp => sale
    assume(endSecs > 0);
    // -------------------------------------------
    // Royalties
    // -------------------------------------------
    //assume(distr.sum() <= royaltyCap);
    //assume(royaltyCap == (10 * floorPrice) / 1000000);
    // -------------------------------------------
  });
  Auctioneer.publish(
    tokenAmount,
    rewardAmount,
    startPrice,
    floorPrice,
    endSecs
    // -------------------------------------------
    // Royalties
    // -------------------------------------------
    //addrs,
    //distr,
    //royaltyCap
    // -------------------------------------------
  )
    .pay([amt + rewardAmount + SERIAL_VER, [tokenAmount, token]])
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  require(tokenAmount > 0);
  require(rewardAmount > 0);
  require(floorPrice > 0);
  require(floorPrice <= startPrice); // fp < sp => auction, fp == sp => sale
  require(endSecs > 0);
  // ---------------------------------------------
  // Royalties
  // ---------------------------------------------
  //require(distr.sum() <= royaltyCap);
  //require(royaltyCap == (10 * floorPrice) / 1000000);
  // ---------------------------------------------
  transfer(amt).to(addr);
  v.startPrice.set(startPrice);
  v.floorPrice.set(floorPrice);
  v.endSecs.set(endSecs);
  v.token.set(token);
  v.tokenP.set(tokenP);
  v.closed.set(false);
  v.manager.set(Auctioneer);
  Auctioneer.interact.signal();
  const referenceConcensusSecs = lastConsensusSecs();
  const dk = calc(
    startPrice - floorPrice,
    endSecs - referenceConcensusSecs,
    precision
  ).i.i;
  v.priceChangePerSec.set(dk / precision);

  const [keepGoing, currentPrice] = parallelReduce([true, startPrice])
    .define(() => {
      v.currentPrice.set(currentPrice);
    })
    .invariant(balance() >= rewardAmount && balance(tokenP) >= 0)
    .while(keepGoing)
    // Touch the contract to update the current price
    .api(
      a.touch,
      () => assume(currentPrice >= floorPrice),
      () => [0, [0, tokenP]],
      (k) => {
        require(currentPrice >= floorPrice);
        k(null);
        return [
          true,
          priceFunc(startPrice, floorPrice, referenceConcensusSecs, dk),
        ];
      }
    )
    // Accept offer to pay for the token
    .api(
      a.acceptOffer,
      () => assume(true),
      () => [1000000, [currentPrice, tokenP]], // 1 ALGO + Current Price in TokenP
      (k) => {
        require(true);
        k(null);
        // ---------------------------------------
        // Royalties
        // ---------------------------------------
        /*
        const cent = currentPrice / 100;
        const partTake = (currentPrice - cent) / royaltyCap;
        const distrTake = distr.slice(0, DIST_LENGTH).sum();
        const sellerTake = currentPrice - cent - partTake * distrTake;
        transfer(cent).to(addr);
        transfer(partTake * distr[0]).to(addrs[0]);
        transfer(sellerTake).to(Auctioneer);
        */
        // ---------------------------------------
        transfer([[balance(token), token]]).to(this);
        transfer(balance(tokenP), tokenP).to(Auctioneer);
        transfer(1000000).to(addr);
        return [false, currentPrice];
      }
    )
    // Cancel the auction and be returned the token
    .api(
      a.cancel,
      () => assume(this === Auctioneer),
      () => [100000, [0, tokenP]], // 0.1 ALGO
      (k) => {
        require(this === Auctioneer);
        k(null);
        transfer([[balance(token), token]]).to(this);
        transfer(100000).to(addr);
        return [false, 0];
      }
    )
    .timeout(false);
  v.closed.set(true); // Set View Closed
  commit();

  Relay.only(() => {
    const rAddr = this;
  });
  Relay.publish(rAddr);
  transfer(balance()).to(rAddr);
  transfer(balance(token), token).to(rAddr);
  transfer(balance(tokenP), tokenP).to(rAddr);
  commit();
  exit();

  // REM Auction over
  // REM Relay races to reward while distributing proceeds

  // ---------------------------------------------
  // Royalties
  // ---------------------------------------------
  /*
  Relay.publish();
  const cent = currentPrice / 100;
  const partTake = (currentPrice - cent) / royaltyCap;
  const distrTake = distr.slice(1, DIST_LENGTH - 1).sum();
  const recvAmount = balance() - partTake * distrTake; // REM includes reward amount
  transfer(partTake * distr[1]).to(addrs[1]);
  transfer(partTake * distr[2]).to(addrs[2]);
  transfer(partTake * distr[3]).to(addrs[3]);
  commit();

  Relay.publish();
  transfer(partTake * distr[4]).to(addrs[4]);
  transfer(partTake * distr[5]).to(addrs[5]);
  transfer(partTake * distr[6]).to(addrs[6]);
  commit();

  Relay.only(() => {
    const rAddr = this;
  });
  Relay.publish(rAddr);
  transfer(partTake * distr[7]).to(addrs[7]);
  transfer(partTake * distr[8]).to(addrs[8]);
  transfer(partTake * distr[9]).to(addrs[9]);
  transfer(recvAmount).to(rAddr);
  transfer([[balance(token), token]]).to(rAddr);
  commit();
  exit();
  */
  // ---------------------------------------------
};
// -----------------------------------------------
