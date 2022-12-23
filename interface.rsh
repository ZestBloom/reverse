"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: Sale (token)
// Version: 0.0.2 - fix extra amount, add safe accept
// Requires Reach v0.1.7
// -----------------------------------------------

import {
  State as BaseState,
  TokenState,
  Params as BaseParams,
  view,
  baseState,
  baseEvents
} from "@KinnFoundation/base#base-v0.1.11r14:interface.rsh";

// CONSTANTS

const SERIAL_VER = 0;

// TYPES

export const TokenSaleState = Struct([
  ["tokenP", Token],
  ["price", UInt],
  ["who", Address],
]);

export const State = Struct([
  ...Struct.fields(BaseState),
  ...Struct.fields(TokenState),
  ...Struct.fields(TokenSaleState),
]);

export const TokenSaleParams = Object({
  tokenAmount: UInt, // NFT token amount
  price: UInt, // 1 ALGO
});

export const Params = Object({
  ...Object.fields(BaseParams),
  ...Object.fields(TokenSaleParams),
});

// FUN

const fState = (State) => Fun([], State);
const fAcceptOffer = Fun([], Null);
const fSafeAcceptOffer = Fun([], Null);
const fCancel = Fun([], Null);

// REMOTE FUN

export const rState = (ctc, State) => {
  const r = remote(ctc, { state: fState(State) });
  return r.state();
};

// INTERACTS

export const Participants = () => [
  Participant("Manager", {
    getParams: Fun([], Params),
  }),
  Participant("Relay", {}),
];

export const Views = () => [View(view(State))];

export const Event = () => [Events({ ...baseEvents })];

export const Api = () => [
  API({
    acceptOffer: fAcceptOffer,
    safeAcceptOffer: fSafeAcceptOffer,
    cancel: fCancel,
  }),
];

export const App = (map) => {
  const [
    { amt, ttl, tok0: token, tok1: tokenP },
    [addr, _],
    [Manager, Relay],
    [v],
    [a],
    [e],
  ] = map;
  Manager.only(() => {
    const { tokenAmount, price } = declassify(interact.getParams());
    const extraAmount = price < 100 ? 1_000_000 : 0;
  });
  Manager.publish(tokenAmount, price, extraAmount)
    .check(() => {
      check(tokenAmount > 0, "token amount must be greater than 0");
      check(price > 0, "price must be greater than 0");
    })
    .pay([amt + SERIAL_VER + extraAmount, [tokenAmount, token]])
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt + SERIAL_VER + extraAmount).to(addr);
  e.appLaunch();

  const initialState = {
    ...baseState(Manager),
    who: Manager,
    token,
    tokenP,
    tokenAmount,
    price,
  };

  const [s, remaining] = parallelReduce([initialState, 0])
    .define(() => {
      v.state.set(State.fromObject(s));
    })
    .invariant(balance() == 0, "balance accurate")
    .invariant(
      implies(!s.closed, balance(token) == s.tokenAmount),
      "token balance accurate before close"
    )
    .invariant(
      implies(s.closed, balance(token) == 0),
      "token balance accurate after close"
    )
    .invariant(
      implies(!s.closed, balance(tokenP) == 0),
      "payment token balance accurate"
    )
    .invariant(
      implies(s.closed, balance(tokenP) == remaining),
      "payment token balance accurate"
    )
    .while(!s.closed)
    .paySpec([tokenP])
    // api: acceptOffer
    .api_(a.safeAcceptOffer, () => {
      return [
        [0, [s.price, tokenP]],
        (k) => {
          k(null);
          const cent = s.price / 100;
          transfer([[s.price - cent, tokenP]]).to(s.manager);
          transfer([[s.tokenAmount, token]]).to(this);
          return [
            {
              ...s,
              closed: true,
              who: this,
            },
            cent,
          ];
        },
      ];
    })
    // api: acceptOffer
    .api_(a.acceptOffer, () => {
      return [
        [0, [s.price, tokenP]],
        (k) => {
          k(null);
          const cent = s.price / 100;
          transfer([[s.price - cent, tokenP]]).to(s.manager);
          transfer([[s.tokenAmount, token]]).to(this);
          transfer([[cent, tokenP]]).to(addr);
          return [
            {
              ...s,
              closed: true,
              who: this,
            },
            0,
          ];
        },
      ];
    })
    // api: cancel
    .api_(a.cancel, () => {
      check(this === s.manager, "Only the manager can cancel the auction");
      return [
        (k) => {
          k(null);
          transfer([[s.tokenAmount, token]]).to(this);
          return [
            {
              ...s,
              closed: true,
            },
            0,
          ];
        },
      ];
    })
    .timeout(false);
  e.appClose();
  commit();
  Relay.publish();
  transfer([[remaining, tokenP]]).to(addr);
  commit();
  exit();
};
// -----------------------------------------------
