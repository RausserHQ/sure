require "test_helper"

class Assistant::Function::GetTransactionsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @transaction = transactions(:one)
    @function = Assistant::Function::GetTransactions.new(@user)
  end

  test "returns transaction ids and notes" do
    @transaction.entry.update!(notes: "Visible note")

    result = @function.call(
      "page" => 1,
      "order" => "asc",
      "search" => @transaction.entry.name
    )

    transaction = result[:transactions].find { |item| item[:id] == @transaction.id }

    assert_not_nil transaction
    assert_equal @transaction.entry.notes, transaction[:notes]
  end

  test "exposes signed stored amounts and ledger flags without changing the existing amount" do
    entry = @transaction.entry
    entry.update!(amount: -42, excluded: true, source: "plaid")
    @transaction.update!(extra: { "plaid" => { "pending" => true } })

    item = @function.call("search" => entry.name)[:transactions].find { |t| t[:id] == @transaction.id }

    assert_equal 42, item[:amount]
    assert_equal(-42, item[:signed_amount])
    assert_equal "income", item[:classification]
    assert_equal "standard", item[:kind]
    assert_equal true, item[:excluded]
    assert_equal true, item[:pending]
    assert_equal "plaid", item[:source]
    assert_equal false, item[:is_transfer]
    assert_nil item[:transfer_id]
    assert_nil item[:counterpart_transaction_id]
    assert_nil item[:counterpart_account_id]
    assert_nil item[:counterpart_account_name]
  end

  test "exposes matched payments and transfers from both sides" do
    outflow = transactions(:transfer_out)
    inflow = transactions(:transfer_in)
    transfer = transfers(:one)
    outflow.update!(kind: "cc_payment")
    inflow.update!(kind: "funds_movement")

    [ [ outflow, inflow ], [ inflow, outflow ] ].each do |transaction, counterpart|
      item = @function.call("search" => transaction.entry.name)[:transactions].find { |t| t[:id] == transaction.id }

      assert_equal transaction.kind, item[:kind]
      assert_equal transaction.entry.amount, item[:signed_amount]
      assert_equal true, item[:is_transfer]
      assert_equal transfer.id, item[:transfer_id]
      assert_equal counterpart.id, item[:counterpart_transaction_id]
      assert_equal counterpart.entry.account_id, item[:counterpart_account_id]
      assert_equal counterpart.entry.account.name, item[:counterpart_account_name]
    end
  end

  test "exposes loan payments and unmatched payment kinds without inventing a counterpart" do
    entry = Entry.create!(account: accounts(:depository), name: "Unmatched loan payment",
                          date: Date.current, amount: 75, currency: "USD",
                          entryable: Transaction.new(kind: "loan_payment"))

    item = @function.call("search" => entry.name)[:transactions].find { |t| t[:id] == entry.entryable.id }

    assert_equal "loan_payment", item[:kind]
    assert_equal 75, item[:signed_amount]
    assert_equal true, item[:is_transfer]
    assert_equal false, item[:pending]
    assert_equal false, item[:excluded]
    assert_nil item[:source]
    assert_nil item[:transfer_id]
    assert_nil item[:counterpart_transaction_id]
    assert_nil item[:counterpart_account_id]
    assert_nil item[:counterpart_account_name]
  end

  test "exposes an unmatched credit card payment without transfer metadata" do
    entry = Entry.create!(account: accounts(:depository), name: "Unmatched card payment",
                          date: Date.current, amount: 35, currency: "USD",
                          entryable: Transaction.new(kind: "cc_payment"))

    item = @function.call("search" => entry.name)[:transactions].find { |t| t[:id] == entry.entryable.id }

    assert_equal "cc_payment", item[:kind]
    assert_equal true, item[:is_transfer]
    assert_nil item[:transfer_id]
    assert_nil item[:counterpart_transaction_id]
  end

  test "does not expose a counterpart account inaccessible to the user" do
    outflow = transactions(:transfer_out)
    outflow.update!(kind: "cc_payment")
    accounts(:credit_card).account_shares.delete_all

    item = Assistant::Function::GetTransactions.new(users(:family_member)).call(
      "search" => outflow.entry.name
    )[:transactions].find { |t| t[:id] == outflow.id }

    assert_not_nil item
    assert_equal transfers(:one).id, item[:transfer_id]
    assert_nil item[:counterpart_transaction_id]
    assert_nil item[:counterpart_account_id]
    assert_nil item[:counterpart_account_name]
  end

  test "excludes transactions from inaccessible accounts" do
    hidden_entry = Entry.create!(
      account: accounts(:investment),
      name: "Private investment transaction",
      date: Date.current,
      amount: 100,
      currency: "USD",
      entryable: Transaction.new
    )
    hidden_entry.update!(notes: "Private note")

    result = Assistant::Function::GetTransactions.new(users(:family_member)).call(
      "page" => 1,
      "order" => "asc",
      "search" => hidden_entry.name
    )

    assert_empty result[:transactions]
  end

  test "translates the documented Uncategorized category alias to the filter sentinel" do
    uncategorized_entry = Entry.create!(
      account: accounts(:depository),
      name: "AI uncategorized lookup",
      date: Date.current,
      amount: 42,
      currency: "USD",
      entryable: Transaction.new
    )

    result = @function.call("categories" => [ "Uncategorized" ])
    result_ids = result[:transactions].map { |t| t[:id] }

    assert_includes result_ids, uncategorized_entry.entryable.id
  end

  test "a real category literally named Uncategorized takes priority over the alias translation" do
    family = @user.family
    lookalike_category = family.categories.create!(name: "Uncategorized", color: "#123456")

    lookalike_entry = Entry.create!(
      account: accounts(:depository),
      name: "AI lookalike category lookup",
      date: Date.current,
      amount: 42,
      currency: "USD",
      entryable: Transaction.new(category: lookalike_category)
    )

    truly_uncategorized_entry = Entry.create!(
      account: accounts(:depository),
      name: "AI truly uncategorized lookup",
      date: Date.current,
      amount: 42,
      currency: "USD",
      entryable: Transaction.new
    )

    result = @function.call("categories" => [ "Uncategorized" ])
    result_ids = result[:transactions].map { |t| t[:id] }

    assert_includes result_ids, lookalike_entry.entryable.id
    assert_not_includes result_ids, truly_uncategorized_entry.entryable.id
  end

  test "schema no longer inlines user data enums" do
    schema = @function.params_schema

    %i[accounts categories merchants tags].each do |key|
      items = schema[:properties][key][:items]

      assert_equal({ type: "string" }, items, "#{key} should be a plain string array")
    end
  end

  test "honors page_size" do
    result = @function.call("page_size" => 1)

    assert_equal 1, result[:page_size]
    assert_equal 1, result[:transactions].size
    assert result[:total_pages] > 1
  end

  test "sorts by absolute amount" do
    result = @function.call("sort_by" => "amount", "order" => "desc")

    amounts = result[:transactions].map { |t| t[:amount].abs }

    assert_equal amounts.sort.reverse, amounts
  end

  test "filters by type" do
    result = @function.call("types" => [ "income" ])

    assert result[:transactions].any?
    assert result[:transactions].all? { |t| t[:classification] == "income" }
  end

  test "filters by account_ids and ignores inaccessible ids" do
    accessible_account = @transaction.entry.account

    result = @function.call("account_ids" => [ accessible_account.id ])

    assert result[:transactions].any?
    assert result[:transactions].all? { |t| t[:account] == accessible_account.name }

    member_result = Assistant::Function::GetTransactions.new(users(:family_member)).call(
      "account_ids" => [ accounts(:investment).id ]
    )

    assert_empty member_result[:transactions]
  end
end
