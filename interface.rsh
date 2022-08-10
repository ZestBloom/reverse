"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Reverse Auction
// Author: Nicholas Shellabarger
// Version: 0.4.2 - fix cancel, add seller addr
// Requires Reach v0.1.7
// -----------------------------------------------

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

const SERIAL_VER = 1; // serial version of reach app reserved to release identical contracts under a separate plana id
// regarding plan ids, the plan ids is the md5 of the approval program in algorand

const DIST_LENGTH = 10; // number of slots to distribute proceeds after sale

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

// calculate slope of line to determine price
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
      addrs: Array(Address, DIST_LENGTH), // [addr, addr, addr, addr, addr, addr, addr, addr, addr, addr]
      distr: Array(UInt, DIST_LENGTH), // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      royaltyCap: UInt, // 10
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
    token: Token,
    currentPrice: UInt,
    startPrice: UInt,
    floorPrice: UInt,
    closed: Bool,
    endSecs: UInt,
    priceChangePerSec: UInt,
    seller: Address,
  }),
];

export const Api = () => [
  API({
    touch: Fun([], Null),
    acceptOffer: Fun([], Null),
    cancel: Fun([], Null),
  }),
];

export const App = (map) => {
  const [{ amt, ttl, tok0: token }, [addr, _], [Auctioneer, Relay], [v], [a], _] = map;
  Auctioneer.only(() => {
    const {
      tokenAmount,
      rewardAmount,
      startPrice,
      floorPrice,
      endSecs,
      addrs,
      distr,
      royaltyCap,
    } = declassify(interact.getParams());
    assume(tokenAmount > 0);
    assume(rewardAmount > 0);
    assume(floorPrice > 0);
    assume(floorPrice <= startPrice); // fp < sp => auction, fp == sp => sale
    assume(endSecs > 0);
    assume(distr.sum() <= royaltyCap);
    assume(royaltyCap == (10 * floorPrice) / 1000000);
  });
  Auctioneer.publish(
    tokenAmount,
    rewardAmount,
    startPrice,
    floorPrice,
    endSecs,
    addrs,
    distr,
    royaltyCap
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
  require(distr.sum() <= royaltyCap);
  require(royaltyCap == (10 * floorPrice) / 1000000);
  transfer(amt).to(addr);
  v.startPrice.set(startPrice);
  v.floorPrice.set(floorPrice);
  v.endSecs.set(endSecs);
  v.token.set(token);
  v.closed.set(false);
  v.seller.set(Auctioneer);
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
    .invariant(balance() >= rewardAmount)
    .while(keepGoing)
    // api: updates current price
    .api(
      a.touch,
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
    // api: accepts offer
    .api(
      a.acceptOffer,
      () => assume(true),
      () => currentPrice,
      (k) => {
        require(true);
        k(null);
        const cent = currentPrice / 100;
        const partTake = (currentPrice - cent) / royaltyCap;
        const distrTake = distr.slice(0, DIST_LENGTH).sum();
        const sellerTake = currentPrice - cent - partTake * distrTake;
        transfer(cent).to(addr);
        transfer(partTake * distr[0]).to(addrs[0]);
        transfer(sellerTake).to(Auctioneer);
        transfer([[balance(token), token]]).to(this);
        return [false, currentPrice];
      }
    )
    // api: cancels auction
    .api(
      a.cancel,
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
  v.closed.set(true); // Set View Closed
  commit();

  // REM Auction over
  // REM Relay races to reward while distributing proceeds

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
};
// -----------------------------------------------