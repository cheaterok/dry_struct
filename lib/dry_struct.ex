defmodule DryStruct do
  @moduledoc """
  Macros for defining structs without boilerplate.

  Tries to achieve same goal as typed_struct library:
  https://github.com/ejpcmac/typed_struct

  Not production ready or anything, just a project to get familiar with Elixir macros.
  """

  defmodule Field do
    @moduledoc false

    @enforce_keys ~w(name type default default_set? enforce?)a
    defstruct @enforce_keys

    @type t(value) :: %__MODULE__{
      name: atom(),
      type: Macro.t(),
      default: value | nil,
      default_set?: boolean(),
      enforce?: boolean()
    }

    @type t :: t(any())
  end

  defmacro __using__([]) do
    quote do
      import unquote(__MODULE__), only: [drystruct: 1, drystruct: 2]
    end
  end

  defmacro drystruct(options \\ [], [do: ast] = _block) do
    global_enforce? = Keyword.get(options, :enforce, false)

    fields =
      ast
      |> block_to_field_asts()
      |> Enum.map(&field_ast_to_field(&1, global_enforce?))

    enforced_keys =
      fields
      |> Stream.filter(&enforce_field?/1)
      |> Enum.map(& &1.name)

    defstruct_kwl = Enum.map(fields, &field_to_defstruct_key/1)
    type_kwl = Enum.map(fields, &field_to_type_keyword/1)

    type_ast = quote do: t :: %__MODULE__{unquote_splicing(type_kwl)}
    spec_ast =
      if options[:opaque] do
        quote do: @opaque unquote(type_ast)
      else
        quote do: @type unquote(type_ast)
      end

    struct_ast =
      quote do
        @enforce_keys unquote(enforced_keys)
        defstruct unquote(defstruct_kwl)

        unquote(spec_ast)
      end

    ast =
      if module_name = options[:module] do
        quote do
          defmodule unquote(module_name) do
            unquote(struct_ast)
          end
        end
      else
        struct_ast
      end

    ast
  end

  @spec block_to_field_asts(Macro.t()) :: [Macro.t()]
  defp block_to_field_asts({:__block__, _context, fields}), do: fields
  defp block_to_field_asts([]), do: []
  defp block_to_field_asts(field), do: [field]

  @spec field_ast_to_field(Macro.t(), boolean()) :: Field.t()
  defp field_ast_to_field({:field, _context, field_ast}, global_enforce?) do
    [name, type, options] =
      case field_ast do
        [name, type] -> [name, type, []]
        [_name, _type, _options] = v -> v
      end

    {default, default_set?} =
      case Keyword.fetch(options, :default) do
        {:ok, value} -> {value, true}
        :error -> {nil, false}
      end

    %Field{
      name: name,
      type: type,
      default: default,
      default_set?: default_set?,
      enforce?: Keyword.get(options, :enforce, global_enforce?)
    }
  end

  @spec enforce_field?(Field.t()) :: boolean()
  defp enforce_field?(%Field{default_set?: false, enforce?: true}), do: true
  defp enforce_field?(_field), do: false

  @spec field_to_defstruct_key(Field.t(v)) :: {atom(), v} | atom() when v: any()
  defp field_to_defstruct_key(field) do
    if field.default_set? do
      {field.name, field.default}
    else
      field.name
    end
  end

  @spec field_to_type_keyword(Field.t()) :: {atom(), Macro.t()}
  defp field_to_type_keyword(field) do
    specs =
      case field.type do
        {:|, _, specs} -> specs
        spec -> [spec]
      end

    signature_has_nil? = Enum.member?(specs, nil)

    needs_nil_in_signature? = (
      not field.enforce?
      and is_nil(field.default)
      and not signature_has_nil?
    )

    type =
      if needs_nil_in_signature? do
        quote do: unquote(field.type) | nil
      else
        field.type
      end

    {field.name, type}
  end
end
