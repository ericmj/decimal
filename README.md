# Decimal

Arbitrary precision decimal arithmetic for Elixir.

Documentation: http://ericmj.github.io/decimal

## Usage

Add Decimal as a dependency in your `mix.exs` file.

```elixir
def deps do
  [ { :decimal, github: "ericmj/decimal" } ]
end
```

After you are done, run `mix deps.get` in your shell to fetch and compile Decimal. Start an interactive Elixir shell with `iex -S mix`.

```iex
iex> alias Decimal, as: D
nil
iex> D.add(D.new(21), D.new(21))
#Decimal<42>
iex> D.div(D.new(1), D.new(3))
#Decimal<0.333333333>

```

## Examples

### Using the context

### Flags and traps

### Mitigating rounding errors

## License

   Copyright 2013 Eric Meadows-Jönsson

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
