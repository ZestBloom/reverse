"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Reverse Auction
// Author: Nicholas Shellabarger
// Version: 0.4.2 - fix cancel, add seller addr
// Requires Reach v0.1.7
// -----------------------------------------------

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

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

const depositerInteract = {
  signal: Fun([], Null)
};

const auctioneerInteract = {
  getParams: Fun(
    [],
    Object({
      tokenAmount: UInt, // NFT token amount
      rewardAmount: UInt, // 1 ALGO
      token: Token, // NFT token
      startPrice: UInt, // 100
      floorPrice: UInt, // 1
      endSecs: UInt, // 1
      addrs: Array(Address, 5),
      distr: Array(UInt, 5),
      royaltyCap: UInt,
    })
  ),
};

// PARTICIPANTS

export const Participants = () => [
  Participant("Auctioneer", auctioneerInteract),
  Participant("Depositer", depositerInteract),
  Participant("Relay", relayInteract),
];

export const Views = () => [
  View("Auction", {
    manager: Address, // Standard View: Manager Address 
    token: Token,
    currentPrice: UInt,
    startPrice: UInt,
    floorPrice: UInt,
    closed: Bool,
    endSecs: UInt,
    priceChangePerSec: UInt,
    seller: Address
  }),
];

export const Api = () => [
  API("Bid", {
    touch: Fun([], Null),
    acceptOffer: Fun([], Null),
    cancel: Fun([], Null),
  }),
];

export const App = (map) => {
  const [[addr, _, addr2], [Auctioneer, Depositer, Relay], [Auction], [Bid]] = map;

  Auctioneer.only(() => {
    const {
      tokenAmount,
      rewardAmount,
      token,
      startPrice,
      floorPrice,
      endSecs,
      addrs,
      distr,
      royaltyCap,
    } = declassify(interact.getParams());
    assume(this == addr2);
    assume(tokenAmount > 0);
    assume(rewardAmount > 0);
    assume(floorPrice > 0);
    assume(floorPrice <= startPrice); // fp < sp => auction, fp == sp => sale
    assume(endSecs > 0);
    assume(distr.sum() <= royaltyCap);
    assume(royaltyCap == (10 * floorPrice) / 1000000);
  });
  Auctioneer.publish(
    token,
    tokenAmount,
    rewardAmount,
    startPrice,
    floorPrice,
    endSecs,
    addrs,
    distr,
    royaltyCap
  )
  .timeout(relativeTime(100), () => {
    Anybody.publish();
    commit();
    exit();
  });

  require(Auctioneer == addr2);
  require(tokenAmount > 0);
  require(rewardAmount > 0);
  require(floorPrice > 0);
  require(floorPrice <= startPrice); // fp < sp => auction, fp == sp => sale
  require(endSecs > 0);
  require(distr.sum() <= royaltyCap);
  require(royaltyCap == (10 * floorPrice) / 1000000);


  Depositer.set(Auctioneer);

  commit();

  Depositer.pay([rewardAmount, [tokenAmount, token]])
  .timeout(relativeTime(100), () => {
    Anybody.publish();
    commit();
    exit();
  });; 

  Auction.startPrice.set(startPrice);
  Auction.floorPrice.set(floorPrice);
  Auction.endSecs.set(endSecs);
  Auction.token.set(token);
  Auction.closed.set(false);
  Auction.seller.set(Auctioneer);

  Depositer.interact.signal();

  // Depositer done

  const referenceConcensusSecs = lastConsensusSecs();

  const dk = calc(
    startPrice - floorPrice,
    endSecs - referenceConcensusSecs,
    precision
  ).i.i;
  Auction.priceChangePerSec.set(dk / precision);
  const [keepGoing, currentPrice] = parallelReduce([true, startPrice])
    .define(() => {
      Auction.currentPrice.set(currentPrice);
    })
    .invariant(balance() >= rewardAmount)
    .while(keepGoing)
    .api(
      Bid.touch,
      () => assume(currentPrice >= floorPrice),
      () => 0,
      (k) => {
        require(currentPrice >= floorPrice);
        k(null);
        return [
          true,
          priceFunc(startPrice, floorPrice, referenceConcensusSecs, dk),
        ];
      }
    )
    .api(
      Bid.acceptOffer,
      () => assume(true),
      () => currentPrice,
      (k) => {
        require(true);
        k(null);
        const cent = currentPrice / 100;
        const partTake = (currentPrice - cent) / royaltyCap;
        const distrTake = distr.slice(0, 5).sum();
        const sellerTake = currentPrice - cent - partTake * distrTake;
        transfer(cent).to(addr);
        transfer(partTake * distr[0]).to(addrs[0]);
        transfer(sellerTake).to(Auctioneer);
        transfer([[balance(token), token]]).to(this);
        return [false, currentPrice];
      }
    )
    .api(
      Bid.cancel,
      () => assume(this === Auctioneer),
      () => 0,
      (k) => {
        require(this === Auctioneer);
        k(null);
        transfer([[balance(token), token]]).to(this);
        return [false, 0];
      }
    )
    .timeout(false);
  Auction.closed.set(true); // Set View Closed
  commit();
  Relay.publish();
  const cent = currentPrice / 100;
  const partTake = (currentPrice - cent) / royaltyCap;
  const distrTake = distr.slice(1, 4).sum();
  const recvAmount = balance() - partTake * distrTake; // REM includes reward amount
  transfer(partTake * distr[1]).to(addrs[1]);
  transfer(partTake * distr[2]).to(addrs[2]);
  transfer(partTake * distr[3]).to(addrs[3]);
  transfer(partTake * distr[4]).to(addrs[4]);
  transfer(recvAmount).to(Relay);
  transfer([[balance(token), token]]).to(Relay);
  commit();
  exit();
};
// -----------------------------------------------
