"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Reverse Auction
// Author: Nicholas Shellabarger
// Version: 1.0.1 - fix token balance invariant
// Requires Reach v0.1.11-rc7 or later
// -----------------------------------------------

// IMPORTS

import { min, max } from "@nash-protocol/starter-kit#lite-v0.1.9r1:util.rsh";

// CONSTS

const SERIAL_VER = 0; // serial version of reach app reserved to release identical contracts under a separate plana id

const DIST_LENGTH = 9; // number of slots to distribute proceeds after sale

const FEE_MIN_ACCEPT = 6000;
const FEE_MIN_CONSTRUCT = 5000;
const FEE_MIN_RELAY = 17000;

// FUNCS

/*
 * precision used in fixed point arithmetic
 */
const precision = 1000000; // 10 ^ 6

/*
 * calculate price based on seconds elapsed since reference secs
 */

const priceFunc =
  (secs) => (startPrice, floorPrice, referenceConcensusSecs, dk) =>
    max(
      floorPrice,
      ((diff) => {
        if (startPrice <= diff) {
          // if is lazy, ? is not lazy (startPrice - diff can underflow)
          return floorPrice;
        } else {
          return startPrice - diff;
        }
      })(
        min(
          ((secs - referenceConcensusSecs) * dk) / precision,
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
      startPrice: UInt, // 100
      floorPrice: UInt, // 1
      endSecs: UInt, // 1
      addrs: Array(Address, DIST_LENGTH), // [addr, addr, addr, addr, addr, addr, addr, addr, addr, addr]
      distr: Array(UInt, DIST_LENGTH), // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      royaltyCap: UInt, // 10
      acceptFee: UInt, // 0.008
      constructFee: UInt, // 0.006
      relayFee: UInt, // 0.007
    })
  ),
  signal: Fun([], Null),
};

export const Event = () => [];

export const Participants = () => [
  Participant("Auctioneer", auctioneerInteract),
  ParticipantClass("Relay", relayInteract),
];

// TODO consider migrating Tuple to Object when it works in future version if there is nothing wrong with the code
const State = Tuple(
  /*maanger*/ Address,
  /*token*/ Token,
  /*tokenAmount*/ UInt,
  /*currentPrice*/ UInt,
  /*startPrice*/ UInt,
  /*floorPrice*/ UInt,
  /*closed*/ Bool,
  /*endSecs*/ UInt,
  /*priceChangePerSec*/ UInt,
  /*addrs*/ Array(Address, DIST_LENGTH), // [addr, addr, addr, addr, addr, addr, addr, addr, addr, addr]
  /*distr*/ Array(UInt, DIST_LENGTH), // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  /*royaltyCap*/ UInt,
  /*who*/ Address
);

const STATE_CURRENT_PRICE = 3;
const STATE_CLOSED = 6;
const STATE_WHO = 12;

export const Views = () => [
  View({
    state: State,
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
  const [
    { amt, ttl, tok0: token },
    [addr, _],
    [Auctioneer, Relay],
    [v],
    [a],
    _,
  ] = map;
  Auctioneer.only(() => {
    const {
      tokenAmount,
      startPrice,
      floorPrice,
      endSecs,
      addrs,
      distr,
      royaltyCap,
      acceptFee,
      constructFee,
      relayFee,
    } = declassify(interact.getParams());
  });

  // Step
  Auctioneer.publish(
    tokenAmount,
    startPrice,
    floorPrice,
    endSecs,
    addrs,
    distr,
    royaltyCap,
    acceptFee,
    constructFee,
    relayFee
  )
    .check(() => {
      check(tokenAmount > 0);
      check(floorPrice > 0);
      check(floorPrice <= startPrice); // fp < sp => auction, fp == sp => sale
      check(endSecs > 0);
      check(distr.sum() <= royaltyCap);
      check(royaltyCap == (10 * floorPrice) / 1000000);
      check(acceptFee >= FEE_MIN_ACCEPT);
      check(constructFee >= FEE_MIN_CONSTRUCT);
      check(relayFee >= FEE_MIN_RELAY);
    })
    .pay([
      amt + (constructFee + acceptFee + relayFee) + SERIAL_VER,
      [tokenAmount, token],
    ])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt + constructFee + SERIAL_VER).to(addr);

  Auctioneer.interact.signal();

  const distrTake = distr.slice(0, DIST_LENGTH).sum();

  const referenceConcensusSecs = thisConsensusSecs();

  const dk = calc(
    startPrice - floorPrice,
    endSecs - referenceConcensusSecs,
    precision
  ).i.i;

  const initialState = [
    /*maanger*/ Auctioneer,
    /*token*/ token,
    /*tokenAmount*/ tokenAmount,
    /*currentPrice*/ startPrice,
    /*startPrice*/ startPrice,
    /*floorPrice*/ floorPrice,
    /*closed*/ false,
    /*endSecs*/ endSecs,
    /*priceChangePerSec*/ dk / precision,
    /*addrs*/ addrs,
    /*distr*/ distr,
    /*royaltyCap*/ royaltyCap,
    /*who*/ Auctioneer
  ];

  // Step

  const [state, who, pTake] = parallelReduce([initialState, Auctioneer, 0])
    .define(() => {
      v.state.set(state);
    })
    .invariant(
      implies(!state[STATE_CLOSED], balance(token) == tokenAmount),
      "token balance accurate before close"
    )
    .invariant(
      implies(state[STATE_CLOSED], balance(token) == 0),
      "token balance accurate after closed"
    )
    .invariant(
      implies(!state[STATE_CLOSED], balance() == acceptFee + relayFee),
      "balance accurate"
    )
    .while(!state[STATE_CLOSED])
    // api: updates current price
    .api_(a.touch, () => {
      check(state[STATE_CURRENT_PRICE] >= floorPrice);
      return [
        (k) => {
          k(null);
          return [
            Tuple.set(
              state,
              STATE_CURRENT_PRICE,
              priceFunc(thisConsensusSecs())(
                startPrice,
                floorPrice,
                referenceConcensusSecs,
                dk
              )
            ),
            who,
            pTake,
          ];
        },
      ];
    })
    // api: accepts offer
    .api_(a.acceptOffer, () => {
      return [
        state[STATE_CURRENT_PRICE],
        (k) => {
          k(null);
          const bal = priceFunc(thisConsensusSecs())(
            startPrice,
            floorPrice,
            referenceConcensusSecs,
            dk
          );
          const diff = state[STATE_CURRENT_PRICE] - bal; // expect state[cp] >= bal
          // TODO concider percent precision approach proposed by @jeapostrophe
          // ie. UInt( ((UInt256(amount) * UInt256(percentPrecision)) * UInt256(percentage)) / UInt256(percentPrecision) )
          // where where percentPrecision is like 10_000 and percentage is like 500, meaning 5%
          const cent = bal / 100; // here
          const partTake = (bal - cent) / royaltyCap;
          const proceedTake = partTake * distrTake;
          const sellerTake = bal - cent - proceedTake;
          transfer(cent).to(addr);
          transfer(sellerTake).to(Auctioneer);
          transfer([acceptFee + diff, [tokenAmount, token]]).to(this);
          return [
            Tuple.set(
              Tuple.set(state, STATE_CLOSED, true),
              STATE_CURRENT_PRICE,
              bal
            ),
            this,
            partTake,
          ];
        },
      ];
    })
    // api: cancels auction
    .api_(a.cancel, () => {
      check(this === Auctioneer);
      return [
        (k) => {
          k(null);
          transfer([acceptFee, [tokenAmount, token]]).to(this);
          return [Tuple.set(state, STATE_CLOSED, true), who, pTake];
        },
      ];
    })
    .timeout(false);
  v.state.set(Tuple.set(state, STATE_WHO, who));
  commit();

  // Step
  Relay.publish();
  ((recvAmount, pDistr) => {
    transfer(pDistr[0]).to(addrs[0]);
    transfer(pDistr[1]).to(addrs[1]);
    transfer(pDistr[2]).to(addrs[2]);
    transfer(pDistr[3]).to(addrs[3]);
    commit();

    // Step
    Relay.publish();
    transfer(pDistr[4]).to(addrs[4]);
    transfer(pDistr[5]).to(addrs[5]);
    transfer(pDistr[6]).to(addrs[6]);
    transfer(pDistr[7]).to(addrs[7]);
    commit();

    Relay.only(() => {
      const rAddr = this;
    });
    // Step
    Relay.publish(rAddr);
    transfer(pDistr[8]).to(addrs[8]);
    transfer(recvAmount).to(rAddr);
    commit();
    exit();
  })(
    balance() - pTake * distrTake,
    distr.map((d) => d * pTake)
  );
};
// -----------------------------------------------
