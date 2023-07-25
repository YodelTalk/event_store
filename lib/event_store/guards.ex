defmodule EventStore.Guards do
  @moduledoc """
  Provides guard functions for input validation, including checks for UUID strings,
  and lists of aggregate IDs or events.
  """

  @doc """
  Checks if the input is a valid UUID string.
  """
  defguard is_uuid(value)
           when is_binary(value) and
                  byte_size(value) == 36 and
                  binary_part(value, 8, 1) == "-" and
                  binary_part(value, 13, 1) == "-" and
                  binary_part(value, 18, 1) == "-" and
                  binary_part(value, 23, 1) == "-"

  @doc """
  Checks if the input is a list of valid UUID strings.
  """
  defguard is_uuids(value) when is_list(value) and is_uuid(hd(value))

  @doc """
  Checks if the input is a valid UUID string or a list of valid UUID strings.
  """
  defguard is_one_or_more_uuids(value) when is_uuid(value) or is_uuids(value)

  @doc """
  Checks if the input is a list of atoms.
  """
  defguard is_atoms(value) when is_list(value) and is_atom(hd(value))

  @doc """
  Checks if the input is an atom or a list of atoms.
  """
  defguard is_one_or_more_atoms(value) when is_atom(value) or is_atoms(value)
end
