---
layout: post
title:  "Collectable: Custom Data Structures in Elixir, part 2"
date:   2020-09-19 12:00:00 -0600
categories: elixir protocol collectable
permalink: /elixir/custom_data_structures/collectable
---

In the [first post of this series](enumerable) we began creating a custom Array data structure. We
defined functions to look at the contents and sizes of arrays, and we made our arrays enumerable
with the [Enumerable](https://hexdocs.pm/elixir/Enumerable.html) protocol. In this post we'll
looking at putting elements into arrays. We'll also implement the
[Collectable](https://hexdocs.pm/elixir/Collectable.html) protocol.

If you want to follow along, our files to start will look like they did at the end of the last post:
[lib/array.ex](https://github.com/brettbeatty/array_elixir/blob/1_enumerable/lib/array.ex) and
[test/array_test.exs](https://github.com/brettbeatty/array_elixir/blob/1_enumerable/test/array_test.exs).
If you missed the post you can also clone the example repo and check out the
[1_enumerable](https://github.com/brettbeatty/array_elixir/tree/1_enumerable) branch. The
dependencies in the example repo--credo, dialyxir, and ex_doc--aren't necessary but won't hurt
anything.

## Collectable
The [Collectable](https://hexdocs.pm/elixir/Collectable.html) docs do a great job of explaining the
protocol and its relation to Enumerable:

> [`Enumerable`](https://hexdocs.pm/elixir/Enumerable.html) was designed to support infinite
> collections, resources and other structures with fixed shape. For example, it doesn't make sense
> to insert values into a range, as it has a fixed shape where just the range limits are stored.
>
> The [`Collectable`](https://hexdocs.pm/elixir/Collectable.html) module was designed to fill the
> gap left by the [`Enumerable`](https://hexdocs.pm/elixir/Enumerable.html) protocol.
> [`Collectable.into/1`](https://hexdocs.pm/elixir/Collectable.html#into/1) can be seen as the
> opposite of [`Enumerable.reduce/3`](https://hexdocs.pm/elixir/Enumerable.html#reduce/3). If the
> functions in [`Enumerable`](https://hexdocs.pm/elixir/Enumerable.html) are about taking values
> out, then [`Collectable.into/1`](https://hexdocs.pm/elixir/Collectable.html#into/1) is about
> collecting those values into a structure.

Collectable lets us collect items from an enuerable into something else. It powers
[Enum.into/2](https://hexdocs.pm/elixir/Enum.html#into/2) and the
[:into](https://hexdocs.pm/elixir/Kernel.SpecialForms.html#for/1-the-into-and-uniq-options) option
for comprehensions. We will also use it to power `Array.new/1`.

To implement Collectable, we only need one more function: `Array.push/2`.

### Define Array.push/2
Let's create a function for appending an element to an array. Our test will begin with a two-element
array, push a third, and check that the elements are what we'd expect.
```elixir
defmodule ArrayTest do
  # ...

  describe "push/2" do
    test "appends an element to an array" do
      array = %Array{elements: {nil, nil, :a, :b}, size: 2, start: 2}
      array = Array.push(array, :c)

      assert Array.to_list(array) == [:a, :b, :c]
    end
  end

  # ...
end
```

For now our implementation of `push/2` will be pretty naive; it'll put an element at the next spot
in the tuple and increment the array's size. We'll use our private `element_position/2` to convert
the next array index (its size) to a position within the `elements` tuple.
```elixir
defmodule Array do
  # ...

  @doc """
  Pushes an element to the end of an array.

  ## Examples

      iex> array = Array.new([:a, :b])
      iex> Array.push(array, :c)
      #Array<[:a, :b, :c]>

  """
  @spec push(array :: t(element), element :: element) :: t(element) when element: var
  def push(array, element) do
    position = element_position(array, array.size)

    %{array | elements: put_elem(array.elements, position, element), size: array.size + 1}
  end

  # ...
end
```

With `push/2` defined, we can implement Collectable.

### Implement Collectable.into/1
Unlike Enumerable, Collectable has only one function we need to implement. Similar to
[Enumerable.slice/1](enumerable#implement-enumerableslice1),
[Collectable.into/1](https://hexdocs.pm/elixir/Collectable.html#into/1) does not perform work
directly. It instead returns a tuple with information then used to collect elements.

When `Collectable.into/1` is called it should return two things:
  - accumulator  
    This lets us perform setup or accumulate on more than just our data structure. For our arrays
    this will be the array passed in.
  - collector  
    This function takes an accumulator and a command and performs the appropriate action. It should
    handle three commands:
    - `{:cont, element}`  
      This command intends for `element` to be put into the accumulator. The function should return
      an accumulator.
    - `:done`  
      This command signals completion. It allows us to perform any cleanup and, if needed, convert
      the accumulator to the original collectable type. The function should return a collectable.
    - `:halt`  
      This command means collection was interrupted. As with `:done`, this should perform any
      cleanup, but the interrupted collection will not be used. The function can return any value.

Let's use `Enum.into/2` to test our implementation.
```elixir
defmodule ArrayTest do
  # ...

  describe "Collectable" do
    test "collects elements into an array" do
      array = %Array{elements: {:a, nil, nil, nil}, size: 1, start: 0}
      new_array = Enum.into([:b, :c], array)

      assert Array.to_list(new_array) == [:a, :b, :c]
    end
  end

  # ...
end
```

Our implementation is simple: when it receives a `{:cont, element}` command, it pushes the element
with our new `Array.push/2` function; when it receives a `:done` or a `:halt`, it returns the array.
```elixir
defmodule Array do
  # ...

  defimpl Collectable do
    @impl Collectable
    def into(array) do
      {array, &collect/2}
    end

    @spec collect(array :: Array.t(element), command :: Collectable.command()) :: Array.t(element)
          when element: var
    defp collect(array, command)

    defp collect(array, {:cont, element}) do
      Array.push(array, element)
    end

    defp collect(array, command) when command in [:done, :halt] do
      array
    end
  end

  # ...
end
```

Our arrays are now collectable. We can use that to define an `Array.new/1` that creates a new array
from an enumerable.

### Define Array.new/0 and Array.new/1
We'll create two functions at once here: `new/0` and `new/1`. They could be the same function with a
default parameter, but we'll define them separately. The zero-arity function will create an empty
array, and the one-arity function will create an array from an enumerable.

Let's start with a couple of tests.
```elixir
defmodule ArrayTest do
  # ...

  describe "new/0" do
    test "creates an empty array" do
      array = Array.new()

      assert Array.to_list(array) == []
    end
  end

  describe "new/1" do
    test "creates an array from an enumerable" do
      array = Array.new([:a, :b, :c])

      assert Array.to_list(array) == [:a, :b, :c]
    end
  end

  # ...
end
```

We can define `new/0` first. All it needs to do is create an empty array. This will return an Array
struct with three fields, as explained in the [previous post](enumerable#define-array-struct):
> - `elements`  
>   A tuple containing the elements of the array. This will be at least as large as the number of
>   elements in the array, and we'll need to swap it out for a larger tuple whenever we exceed its
>   capacity.
> - `size`  
>   An integer counting elements in the array. This will increase/decrease as elements are
>   added/removed.
> - `start`  
>   An integer representing where in the `elements` tuple our array starts. This will
>   increase/decrease as elements are removed/added to the front of the array.

Since an array's capacity is tied to the size of its `elements` tuple, we'll introduce a private
function `make_array/1` that returns an array with a given capacity. The need for this function will
be clearer when we start scaling up arrays when they need greater capacity.
```elixir
defmodule Array do
  # ...

  @spec make_array(capacity :: non_neg_integer()) :: t()
  defp make_array(capacity) do
    %__MODULE__{
      elements: :erlang.make_tuple(capacity, nil),
      size: 0,
      start: 0
    }
  end

  # ...
end
```

The function `new/0` can simply call `make_array/1` with an initial, default capacity.
```elixir
defmodule Array do
  # ...

  @initial_capacity 8

  # ...

  @doc """
  Creates an empty array.

  ## Examples

      iex> Array.new()
      #Array<[]>

  """
  @spec new() :: t()
  def new do
    make_array(@initial_capacity)
  end

  # ...
end
```

The function `new/1` will take an enumerable and use `Enum.into/2` to fill an empty array with its
elements.
```elixir
defmodule Array do
  # ...

  @doc """
  Creates an array from an enumerable.

  ## Examples

      iex> Array.new([:a, :b, :c])
      #Array<[:a, :b, :c]>

  """
  @spec new(enumerable :: Enumerable.t()) :: t()
  def new(enumerable) do
    Enum.into(enumerable, new())
  end

  # ...
end
```

We can now create arrays with ease. You can try it out in IEx with `iex -S mix`. However, if you
try to create an array with more than 8 elements, you may notice some strange behavior.
```elixir
iex> 0..8 |> Array.new() |> Array.to_list()
[8, 1, 2, 3, 4, 5, 6, 7, 8]
```

There is an additional `8` where the element `0` should be. This is because our `push/2` function as
written can overwrite elements in the `elements` tuple when an array exceeds its capacity. Instead
we want it to increase the capacity of arrays as needed.

### Increase array capacity as needed
Let's begin with a test of the above scenario: we'll create an array with 8 elements (but get the 8
dynamically with a quick peek at array internals), attempt to push a 9th, and check that all 9
elements show up when we convert the array to a list.
```elixir
defmodule ArrayTest do
  # ...

  describe "push/2" do
    # ...
    
    test "scales up arrays at capacity" do
      capacity = tuple_size(Array.new().elements)

      array =
        0
        |> Range.new(capacity - 1)
        |> Array.new()
        |> Array.push(capacity)

      assert Array.to_list(array) == Enum.to_list(0..capacity)
    end
  end

  # ...
end
```

We can run that test and should get the same result from the section above.

Tuples in Elixir have a fixed size, so when we want to increase an array's capacity, we must create
a new `elements` tuple and copy everything over. We could do that at the tuple level, but since we
have already implemented Enumerable and Collectable, let's put our existing code to work. When
pushing to an at-capacity array, we can collect the elements of the array into a larger array
(created with our private `make_array/1` function) and push to the larger array. An array is at
capacity when its `size` is the same as the size of its `elements` tuple.
```elixir
defmodule Array do
  # ...

  @doc """
  Pushes an element to the end of an array.

  ## Examples

      iex> array = Array.new([:a, :b])
      iex> Array.push(array, :c)
      #Array<[:a, :b, :c]>

  """
  @spec push(array :: t(element), element :: element) :: t(element) when element: var
  def push(array, element)

  def push(array = %{elements: elements, size: size}, element)
      when size == tuple_size(elements) do
    array
    |> Enum.into(make_array(size * 2))
    |> push(element)
  end

  def push(array, element) do
    position = element_position(array, array.size)

    %{array | elements: put_elem(array.elements, position, element), size: array.size + 1}
  end

  # ...
end
```

Pushing to arrays will scale up capacity as needed. Before we conclude this post, let's do one more
thing: we can take advantage of our `new/0` and `new/1` functions for our existing tests.

### Use Array.new/0 and Array.new/1 in tests
A lot of our tests up until this point created arrays using the literal struct syntax. They had to
know about array internals. We can make our tests clearer and a little more resilient by using
`Array.new/0` and `Array.new/1` to create the arrays we use in our tests.
```elixir
defmodule ArrayTest do
  use ExUnit.Case, async: true

  describe "new/0" do
    test "creates an empty array" do
      array = Array.new()

      assert Array.to_list(array) == []
    end
  end

  describe "new/1" do
    test "creates an array from an enumerable" do
      array = Array.new([:a, :b, :c])

      assert Array.to_list(array) == [:a, :b, :c]
    end
  end

  describe "push/2" do
    test "appends an element to an array" do
      array = Array.new([:a, :b])
      array = Array.push(array, :c)

      assert Array.to_list(array) == [:a, :b, :c]
    end

    test "scales up arrays at capacity" do
      capacity = tuple_size(Array.new().elements)

      array =
        0
        |> Range.new(capacity - 1)
        |> Array.new()
        |> Array.push(capacity)

      assert Array.to_list(array) == Enum.to_list(0..capacity)
    end
  end

  describe "shift/1" do
    test "shifts the first element off an array" do
      array = Array.new([:a, :b])

      assert {:ok, :a, new_array} = Array.shift(array)
      assert Array.to_list(new_array) == [:b]
    end

    test "returns :error when shifting off an empty array" do
      array = Array.new()

      assert Array.shift(array) == :error
    end
  end

  describe "size/1" do
    test "returns the size of the array" do
      array = Array.new([:a, :b])

      assert Array.size(array) == 2
    end
  end

  describe "slice/3" do
    test "returns a slice of an array" do
      array = Array.new([:d, :a, :b, :c])
      array = Array.slice(array, 1, 2)

      assert Array.to_list(array) == [:a, :b]
    end

    test "does not allow a slice past end of array" do
      array = Array.new([:a, :b, :c, :d])
      array = Array.slice(array, 2, 4)

      assert Array.to_list(array) == [:c, :d]
    end
  end

  describe "to_list/1" do
    test "converts an array to a list" do
      array = Array.new('bcd')

      assert Array.to_list(array) == 'bcd'
    end
  end

  describe "Collectable" do
    test "collects elements into an array" do
      array = Array.new([:a])
      new_array = Enum.into([:b, :c], array)

      assert Array.to_list(new_array) == [:a, :b, :c]
    end
  end

  describe "Enumerable" do
    test "count is accurate" do
      array = Array.new([nil])

      assert Enum.count(array) == 1
    end

    test "passes everything appropriately to reducer" do
      array = Array.new('abc')

      assert Enum.map(array, &(&1 + 4)) == 'efg'
    end

    test "halts early just fine" do
      array = Array.new('wxyz')

      assert Enum.take(array, 2) == 'wx'
    end

    test "suspends and resumes" do
      array = Array.new([:a, :b, :c])

      assert Enum.zip(array, 1..3) == [a: 1, b: 2, c: 3]
    end

    test "slices work as expected" do
      array = Array.new('cdab')

      assert Enum.slice(array, 1, 2) == 'da'
    end
  end
end
```

This should be the last time we change up the tests so drastically I'll paste the entire contents of
`test/array_test.exs`. Additionally if you want to compare the Array module, you can check out
an example
[`lib/array.ex`](https://github.com/brettbeatty/array_elixir/blob/2_collectable/lib/array.ex).

## Conclusion
Having [Collectable](https://hexdocs.pm/elixir/Collectable.html) implemented alongside
[Enumerable](https://hexdocs.pm/elixir/Enumerable.html) goes a long way towards our arrays feeling
like a real data structure. We can now convert to and from arrays with ease.

You may also have noticed the use of `Array.new/0` and `Array.new/1` in the examples in our
docstrings. These functions will play an integral part when we set up doctests in the next post in
this series, which will focus on the [Inspect](https://hexdocs.pm/elixir/Inspect.html) protocol. If
you're interested in reading that post when it's published, 
[follow me](https://twitter.com/brett_beatty) on Twitter.
