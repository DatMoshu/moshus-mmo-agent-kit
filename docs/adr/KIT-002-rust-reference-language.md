# KIT-002: Rust is the reference module language

- Status: accepted
- Date: 2026-10-30

## Context
Rust modules have the most production use (including BitCraft), the strongest compile-time checks and the most examples. SpacetimeDB 2.14 supports Rust, C#, TypeScript and C++ modules, and IDC in Rust and TypeScript.

## Decision
The reference templates are Rust. A TypeScript single-module template follows the same game and rules. C# module guidance points to the official skill.

## Consequences
Rust needs a toolchain (and the MSVC linker on Windows). TypeScript is offered for web-first teams.
