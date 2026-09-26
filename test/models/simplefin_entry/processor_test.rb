require "test_helper"

class SimplefinEntry::ProcessorTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @simplefin_item = SimplefinItem.create!(
      family: @family,
      name: "Test SimpleFin Bank",
      access_url: "https://example.com/access_token"
    )
    @simplefin_account = SimplefinAccount.create!(
      simplefin_item: @simplefin_item,
      name: "SF Checking",
      account_id: "sf_acc_1",
      account_type: "checking",
      currency: "USD",
      current_balance: 1000,
      available_balance: 1000,
      account: @account
    )
  end

  test "persists extra metadata (raw payee/memo/description and provider extra)" do
    tx = {
      id: "tx_1",
      amount: "-12.34",
      currency: "USD",
      payee: "Pizza Hut",
      description: "Order #1234",
      memo: "Carryout",
      posted: Date.current.to_s,
      transacted_at: (Date.current - 1).to_s,
      extra: { category: "restaurants", check_number: nil }
    }

    assert_difference "@account.entries.count", 1 do
      SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process
    end

    entry = @account.entries.find_by!(external_id: "simplefin_tx_1", source: "simplefin")
    extra = entry.transaction.extra

    assert_equal "Pizza Hut - Order #1234", entry.name
    assert_equal "USD", entry.currency

    # Check extra payload structure
    assert extra.is_a?(Hash), "extra should be a Hash"
    assert extra["simplefin"].is_a?(Hash), "extra.simplefin should be a Hash"
    sf = extra["simplefin"]
    assert_equal "Pizza Hut", sf["payee"]
    assert_equal "Carryout", sf["memo"]
    assert_equal "Order #1234", sf["description"]
    assert_equal({ "category" => "restaurants", "check_number" => nil }, sf["extra"])
  end
  test "does not flag pending when posted is nil but provider pending flag not set" do
    # Previously we inferred pending from missing posted date, but this was too aggressive -
    # some providers don't supply posted dates even for settled transactions
    tx = {
      id: "tx_pending_1",
      amount: "-20.00",
      currency: "USD",
      payee: "Coffee Shop",
      description: "Latte",
      memo: "Morning run",
      posted: nil,
      transacted_at: (Date.current - 3).to_s
    }

    SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process

    entry = @account.entries.find_by!(external_id: "simplefin_tx_pending_1", source: "simplefin")
    sf = entry.transaction.extra.fetch("simplefin")

    assert_equal false, sf["pending"], "expected pending flag to be false when provider doesn't explicitly set pending"
  end

  test "captures FX metadata when tx currency differs from account currency" do
    # Account is USD from setup; use EUR for tx
    t_date = (Date.current - 5)
    p_date = Date.current

    tx = {
      id: "tx_fx_1",
      amount: "-42.00",
      currency: "EUR",
      payee: "Boulangerie",
      description: "Croissant",
      posted: p_date.to_s,
      transacted_at: t_date.to_s
    }

    SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process

    entry = @account.entries.find_by!(external_id: "simplefin_tx_fx_1", source: "simplefin")
    sf = entry.transaction.extra.fetch("simplefin")

    assert_equal "EUR", sf["fx_from"]
    assert_equal t_date.to_s, sf["fx_date"], "fx_date should prefer transacted_at"
  end
  test "flags pending when provider pending flag is true (even if posted provided)" do
    tx = {
      id: "tx_pending_flag_1",
      amount: "-9.99",
      currency: "USD",
      payee: "Test Store",
      description: "Auth",
      memo: "",
      posted: Date.current.to_s, # provider says pending=true should still flag
      transacted_at: (Date.current - 1).to_s,
      pending: true
    }

    SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process

    entry = @account.entries.find_by!(external_id: "simplefin_tx_pending_flag_1", source: "simplefin")
    sf = entry.transaction.extra.fetch("simplefin")
    assert_equal true, sf["pending"], "expected pending flag to be true when provider sends pending=true"
  end

  test "posted==0 treated as missing, entry uses transacted_at date and flags pending" do
    # Simulate provider sending epoch-like zeros for posted and an integer transacted_at
    t_epoch = (Date.current - 2).to_time.to_i
    tx = {
      id: "tx_pending_zero_posted_1",
      amount: "-6.48",
      currency: "USD",
      payee: "Dunkin'",
      description: "DUNKIN #358863",
      memo: "",
      posted: 0,
      transacted_at: t_epoch,
      pending: true
    }

    SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process

    entry = @account.entries.find_by!(external_id: "simplefin_tx_pending_zero_posted_1", source: "simplefin")
    # For depository accounts, processor prefers posted, then transacted; posted==0 should be treated as missing
    assert_equal Time.at(t_epoch).utc.to_date, entry.date, "expected entry.date to use transacted_at when posted==0"
    sf = entry.transaction.extra.fetch("simplefin")
    assert_equal true, sf["pending"], "expected pending flag to be true when posted==0 and/or pending=true"
  end

  test "skips pending transactions when pending inclusion is disabled" do
    Setting.stubs(:syncs_include_pending).returns(false)

    tx = {
      id: "tx_pending_disabled_1",
      amount: "-30.00",
      currency: "USD",
      payee: "Test Store",
      description: "Auth hold",
      posted: Date.current.to_s,
      transacted_at: (Date.current - 1).to_s,
      pending: true
    }

    # Clear the env var so this only exercises the Setting fallback branch of pending_enabled?
    with_env_overrides SIMPLEFIN_INCLUDE_PENDING: nil do
      assert_no_difference "@account.entries.count" do
        SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process
      end
    end
  end

  test "still imports posted transactions when pending inclusion is disabled" do
    Setting.stubs(:syncs_include_pending).returns(false)

    tx = {
      id: "tx_posted_disabled_1",
      amount: "-30.00",
      currency: "USD",
      payee: "Test Store",
      description: "Settled",
      posted: Date.current.to_s,
      transacted_at: (Date.current - 1).to_s,
      pending: false
    }

    with_env_overrides SIMPLEFIN_INCLUDE_PENDING: nil do
      assert_difference "@account.entries.count", 1 do
        SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process
      end
    end
  end

  test "SIMPLEFIN_INCLUDE_PENDING env var takes precedence over Setting" do
    # Setting says "skip pending", but the env var (mirrored via the boot-time config it
    # populates) says "include pending" - env var must win, matching
    # SimplefinItem::Importer#fetch_accounts_data's effective_pending resolution.
    Setting.stubs(:syncs_include_pending).returns(false)
    Rails.configuration.x.simplefin.stubs(:include_pending).returns(true)

    tx = {
      id: "tx_pending_env_override_1",
      amount: "-30.00",
      currency: "USD",
      payee: "Test Store",
      description: "Auth hold",
      posted: Date.current.to_s,
      transacted_at: (Date.current - 1).to_s,
      pending: true
    }

    with_env_overrides SIMPLEFIN_INCLUDE_PENDING: "1" do
      assert_difference "@account.entries.count", 1 do
        SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process
      end
    end
  end

  test "SIMPLEFIN_INCLUDE_PENDING env var disabling pending takes precedence over a permissive Setting" do
    # Mirror of the test above: this is the actual real-world guard scenario the PR
    # fixes - a self-hoster sets SIMPLEFIN_INCLUDE_PENDING=0 while the Setting (UI
    # toggle) still says "include pending". The env var must win and skip the row.
    Setting.stubs(:syncs_include_pending).returns(true)
    Rails.configuration.x.simplefin.stubs(:include_pending).returns(false)

    tx = {
      id: "tx_pending_env_disable_1",
      amount: "-30.00",
      currency: "USD",
      payee: "Test Store",
      description: "Auth hold",
      posted: Date.current.to_s,
      transacted_at: (Date.current - 1).to_s,
      pending: true
    }

    with_env_overrides SIMPLEFIN_INCLUDE_PENDING: "0" do
      assert_no_difference "@account.entries.count" do
        SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process
      end
    end
  end

  test "infers pending when posted is explicitly 0 and transacted_at present (no explicit pending flag)" do
    # Some SimpleFIN banks indicate pending by sending posted=0 + transacted_at, without pending flag
    t_epoch = (Date.current - 1).to_time.to_i
    tx = {
      id: "tx_inferred_pending_1",
      amount: "-15.00",
      currency: "USD",
      payee: "Gas Station",
      description: "Fuel",
      memo: "",
      posted: 0,
      transacted_at: t_epoch
      # Note: NO pending flag set
    }

    SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process

    entry = @account.entries.find_by!(external_id: "simplefin_tx_inferred_pending_1", source: "simplefin")
    sf = entry.transaction.extra.fetch("simplefin")
    assert_equal true, sf["pending"], "expected pending to be inferred from posted=0 + transacted_at present"
  end

  test "does not treat a non-numeric posted value as epoch-zero pending" do
    # Regression: `posted_val.to_i.zero?` would also match malformed strings like
    # "unavailable" (String#to_i coerces non-numeric input to 0), wrongly flagging a
    # settled transaction as pending. Only literal 0 / "0" should count as epoch-zero.
    tx = {
      id: "tx_malformed_posted_1",
      amount: "-11.00",
      currency: "USD",
      payee: "Test Store",
      description: "Settled",
      memo: "",
      posted: "unavailable",
      transacted_at: (Date.current - 1).to_s
      # Note: NO pending flag set
    }

    SimplefinEntry::Processor.new(tx, simplefin_account: @simplefin_account).process

    entry = @account.entries.find_by!(external_id: "simplefin_tx_malformed_posted_1", source: "simplefin")
    sf = entry.transaction.extra.fetch("simplefin")
    assert_equal false, sf["pending"], "expected a non-numeric posted value to not be inferred as pending"
  end

  test "normalizes SimpleFIN loan principal advances as new debt" do
    use_account(accounts(:loan), account_type: "loan")

    entry = process_transaction(
      id: "loan_advance",
      amount: "500.00",
      payee: "Principal Advance",
      description: "PRINCIPAL ADVANCE"
    )

    assert_equal BigDecimal("500.00"), entry.amount
    assert_equal "loan_proceeds", entry.transaction.kind
  end

  test "normalizes SimpleFIN loan principal payments as debt reduction" do
    use_account(accounts(:loan), account_type: "loan")

    entry = process_transaction(
      id: "loan_principal_payment",
      amount: "-200.00",
      payee: "Principal Payment",
      description: "PRINCIPAL PAYMENT"
    )

    assert_equal BigDecimal("-200.00"), entry.amount
    assert_equal "loan_payment", entry.transaction.kind
  end

  test "keeps payroll into a SimpleFIN loan as income that reduces debt" do
    use_account(accounts(:loan), account_type: "loan")

    entry = process_transaction(
      id: "loan_payroll",
      amount: "300.00",
      payee: "Example Employer Payroll",
      description: "EMPLOYER PAYROLL DIRECT DEPOSIT"
    )

    assert_equal BigDecimal("-300.00"), entry.amount
    assert_equal "standard", entry.transaction.kind
  end

  test "classifies an unmatched card payment funded by a SimpleFIN loan" do
    use_account(accounts(:loan), account_type: "loan")

    entry = process_transaction(
      id: "loan_card_payment",
      amount: "-400.00",
      payee: "Example Credit Card",
      description: "AMEX AUTOPAY"
    )

    assert_equal BigDecimal("400.00"), entry.amount
    assert_equal "cc_payment", entry.transaction.kind
    totals = IncomeStatement.new(@family).totals(
      transactions_scope: @family.transactions.where(id: entry.entryable_id), date_range: Date.current..Date.current
    )
    assert_equal Money.new(0, @family.currency), totals.expense_money
  end

  test "distinguishes SimpleFIN credit card refunds from payments" do
    use_account(accounts(:credit_card), account_type: "credit card")

    refund = process_transaction(
      id: "card_refund",
      amount: "25.00",
      payee: "Example Merchant",
      description: "PURCHASE CREDIT"
    )
    payment = process_transaction(
      id: "card_payment",
      amount: "100.00",
      payee: "Payment",
      description: "AUTOPAY PAYMENT - THANK YOU"
    )

    assert_equal BigDecimal("-25.00"), refund.amount
    assert_equal "refund", refund.transaction.kind
    assert_equal BigDecimal("-100.00"), payment.amount
    assert_equal "cc_payment", payment.transaction.kind
  end

  test "principal originals and reversals cancel debt movement" do
    use_account(accounts(:loan), account_type: "loan")

    [ [ "advance", "PRINCIPAL ADVANCE", "500", 500, "loan_proceeds" ],
      [ "advance_reversal", "PRINCIPAL ADVANCE REVERSAL", "-500", -500, "loan_payment" ],
      [ "payment", "PRINCIPAL PAYMENT", "-200", -200, "loan_payment" ],
      [ "payment_reversal", "PRINCIPAL PAYMENT REVERSAL", "200", 200, "loan_proceeds" ] ].each do |id, description, amount, expected, kind|
      entry = process_transaction(id: id, amount: amount, payee: "Loan Servicer", description: description)
      assert_equal expected, entry.amount
      assert_equal kind, entry.transaction.kind
    end

    assert_equal 0, @account.entries.where(external_id: %w[simplefin_advance simplefin_advance_reversal]).sum(:amount)
    assert_equal 0, @account.entries.where(external_id: %w[simplefin_payment simplefin_payment_reversal]).sum(:amount)
  end

  test "interest payment imports as expense rather than card payment" do
    use_account(accounts(:loan), account_type: "loan")
    entry = process_transaction(id: "interest", amount: "-37", payee: "Loan Servicer", description: "INTEREST PAYMENT")

    assert_equal 37, entry.amount
    assert_equal "standard", entry.transaction.kind
    assert_equal "expense", entry.transaction.cashflow_classification
    totals = IncomeStatement.new(@family).totals(transactions_scope: @family.transactions.where(id: entry.entryable_id), date_range: Date.current..Date.current)
    assert_equal Money.new(37, @family.currency), totals.expense_money
    assert_equal Money.new(0, @family.currency), totals.income_money
  end

  test "card credits require evidence and only neutral credits can match transfers" do
    use_account(accounts(:credit_card), account_type: "credit card")
    refund = process_transaction(id: "confirmed_refund", amount: "40", payee: "Example Merchant", description: "PURCHASE CREDIT")
    payment = process_transaction(id: "confirmed_payment", amount: "41", payee: "Card Issuer", description: "AUTOPAY PAYMENT")
    alternate = process_transaction(id: "alternate_payment", amount: "42", payee: "Card Issuer", description: "TRANSFER FROM CHECKING")
    unknown = process_transaction(id: "unknown_credit", amount: "43", payee: "Unknown", description: "CREDIT ADJUSTMENT")

    assert_equal "refund", refund.transaction.kind
    assert_equal "expense", refund.transaction.cashflow_classification
    assert_equal "cc_payment", payment.transaction.kind
    assert_equal "cc_payment", alternate.transaction.kind
    assert_equal "unclassified", unknown.transaction.kind
    assert_equal "unclassified", unknown.transaction.cashflow_classification
    assert_not unknown.excluded?
    unknown_totals = IncomeStatement.new(@family).totals(
      transactions_scope: @family.transactions.where(id: unknown.entryable_id), date_range: Date.current..Date.current
    )
    assert_equal Money.new(0, @family.currency), unknown_totals.income_money
    assert_equal Money.new(0, @family.currency), unknown_totals.expense_money
    search_totals = Transaction::Search.new(@family, filters: { search: "CREDIT ADJUSTMENT" }).totals
    assert_equal Money.new(0, @family.currency), search_totals.income_money
    assert_equal Money.new(0, @family.currency), search_totals.expense_money

    [ 40, 41, 42, 43 ].each do |amount|
      use_account(accounts(:depository), account_type: "checking")
      process_transaction(id: "cash_#{amount}", amount: "-#{amount}", payee: "Bank", description: "Outgoing transfer")
    end
    @family.auto_match_transfers!
    assert_not Transfer.exists?(inflow_transaction_id: refund.entryable_id)
    [ payment, alternate, unknown ].each do |credit|
      assert Transfer.exists?(inflow_transaction_id: credit.entryable_id)
      assert_equal "funds_movement", credit.transaction.reload.kind
    end
    Transfer.find_by!(inflow_transaction_id: unknown.entryable_id).reject!
    assert_equal "unclassified", unknown.transaction.reload.kind
    assert_equal Money.new(0, @family.currency), IncomeStatement.new(@family).totals(
      transactions_scope: @family.transactions.where(id: unknown.entryable_id), date_range: Date.current..Date.current
    ).income_money
  end

  test "matched ambiguous SimpleFIN credit keeps its transfer through repeat import" do
    use_account(accounts(:credit_card), account_type: "credit card")
    credit = process_transaction(id: "repeat_credit", amount: "43", payee: "Unknown", description: "CREDIT ADJUSTMENT")
    assert_equal "unclassified", credit.transaction.kind

    use_account(accounts(:depository), account_type: "checking")
    cash = process_transaction(id: "repeat_cash", amount: "-43", payee: "Bank", description: "Outgoing transfer")
    Family::Syncer.new(@family).perform_post_sync
    transfer = Transfer.find_by!(inflow_transaction: credit.transaction, outflow_transaction: cash.transaction)
    assert_equal "unclassified", credit.transaction.reload.extra["transfer_original_kind"]

    use_account(accounts(:credit_card), account_type: "credit card")
    process_transaction(id: "repeat_credit", amount: "43", payee: "Updated payee", description: "CREDIT ADJUSTMENT")
    Family::Syncer.new(@family).perform_post_sync

    assert_equal "Updated payee", credit.transaction.reload.extra.dig("simplefin", "payee")
    assert_equal transfer.id, credit.transaction.transfer.id
    assert_equal "funds_movement", credit.transaction.kind
    assert_equal "transfer", credit.transaction.cashflow_classification
    assert credit.transaction.transfer?
    assert_equal "unclassified", credit.transaction.extra["transfer_original_kind"]
    assert_includes Transaction::Search.new(@family, filters: { types: [ "transfer" ] }).transactions_scope.pluck(:id), credit.entryable_id
    item = Assistant::Function::GetTransactions.new(users(:family_admin)).call("search" => "CREDIT ADJUSTMENT")[:transactions].find { |txn| txn[:id] == credit.entryable_id }
    assert_equal true, item[:is_transfer]
    assert_equal transfer.id, item[:transfer_id]
    assert_equal "standard", cash.transaction.reload.extra["transfer_original_kind"]
    assert_not credit.user_modified?
    assert_equal(-43, credit.reload.amount)

    transfer.reject!
    assert_equal "unclassified", credit.transaction.reload.kind
  end

  test "legacy matched SimpleFIN credit keeps transfer kinds without restore markers" do
    use_account(accounts(:credit_card), account_type: "credit card")
    credit = process_transaction(id: "legacy_credit", amount: "43", payee: "Unknown", description: "CREDIT ADJUSTMENT")
    use_account(accounts(:depository), account_type: "checking")
    cash = process_transaction(id: "legacy_cash", amount: "-43", payee: "Bank", description: "Outgoing transfer")

    transfer = Transfer.create!(inflow_transaction: credit.transaction, outflow_transaction: cash.transaction)
    credit.transaction.update!(kind: "funds_movement")
    cash.transaction.update!(kind: "funds_movement")
    [ credit, cash ].each do |entry|
      assert_not entry.transaction.reload.extra.key?("transfer_original_kind")
      assert_not entry.user_modified?
    end

    use_account(accounts(:credit_card), account_type: "credit card")
    process_transaction(id: "legacy_credit", amount: "43", payee: "Updated payee", description: "PURCHASE CREDIT")
    use_account(accounts(:depository), account_type: "checking")
    process_transaction(id: "legacy_cash", amount: "-43", payee: "Updated bank", description: "Outgoing transfer")
    Family::Syncer.new(@family).perform_post_sync

    assert_equal transfer.id, credit.transaction.reload.transfer.id
    assert_equal transfer.id, cash.transaction.reload.transfer.id
    assert_equal "Updated payee", credit.transaction.extra.dig("simplefin", "payee")
    [ credit, cash ].each do |entry|
      assert_equal "funds_movement", entry.transaction.kind
      assert_equal "transfer", entry.transaction.cashflow_classification
      assert_not entry.transaction.extra.key?("transfer_original_kind")
      assert_not entry.reload.user_modified?
    end

    transfer.reject!
    assert_equal "standard", credit.transaction.reload.kind
    assert_equal "standard", cash.transaction.reload.kind
  end

  test "synthetic payroll remains income across matching and repeat import" do
    family = families(:empty)
    @simplefin_account.update!(simplefin_item: SimplefinItem.create!(family: family, name: "Synthetic Bank", access_url: "https://example.com/synthetic"))
    checking = family.accounts.create!(name: "Payroll checking", currency: "USD", balance: 0, accountable: Depository.new)
    savings = family.accounts.create!(name: "Payroll savings", currency: "USD", balance: 0, accountable: Depository.new)
    loan = family.accounts.create!(name: "Payroll loan", currency: "USD", balance: 10000, accountable: Loan.new)
    @family = family
    assert Account::OpeningBalanceManager.new(loan).set_opening_balance(balance: 10000, date: Date.yesterday).success?
    payroll = [ [ checking, "checking", "pay_a", 120 ], [ savings, "savings", "pay_b", 180 ],
                [ checking, "checking", "pay_c", 20 ], [ loan, "loan", "pay_d", 80 ] ]
    entries = payroll.map do |account, type, id, amount|
      use_account(account, account_type: type)
      process_transaction(id: id, amount: amount.to_s, payee: "Example Employer", description: "PAYROLL DIRECT DEPOSIT")
    end
    use_account(checking, account_type: "checking")
    unrelated = process_transaction(id: "unrelated", amount: "-80", payee: "Shop", description: "Purchase")

    2.times do
      Family::Syncer.new(family).perform_post_sync
      assert_equal 0, Transfer.where(inflow_transaction_id: entries.map(&:entryable_id)).count
      entries.each { |entry| assert_equal "standard", entry.transaction.reload.kind }
      assert_equal(-80, entries.last.reload.amount)
      balance = Balance::ForwardCalculator.new(loan).calculate.last
      assert_equal 80, balance.non_cash_inflows
      assert_equal 9920, balance.balance
      scope = family.transactions.where(id: (entries + [ unrelated ]).map(&:entryable_id))
      totals = IncomeStatement.new(family).totals(transactions_scope: scope, date_range: Date.current..Date.current)
      assert_equal Money.new(400, family.currency), totals.income_money
      assert_equal Money.new(80, family.currency), totals.expense_money
      payroll.each do |account, type, id, amount|
        use_account(account, account_type: type)
        process_transaction(id: id, amount: amount.to_s, payee: "Example Employer", description: "PAYROLL DIRECT DEPOSIT")
      end
    end
    assert_equal 5, family.entries.where(external_id: (payroll.map { |row| "simplefin_#{row[2]}" } + [ "simplefin_unrelated" ])).count
  end

  private
    def use_account(account, account_type:)
      @account = account
      @simplefin_account.update!(account: account, account_type: account_type)
    end

    def process_transaction(id:, amount:, payee:, description:)
      SimplefinEntry::Processor.new(
        {
          id: id,
          amount: amount,
          currency: "USD",
          payee: payee,
          description: description,
          posted: Date.current.to_s,
          transacted_at: Date.current.to_s,
          pending: false
        },
        simplefin_account: @simplefin_account
      ).process

      @account.entries.find_by!(external_id: "simplefin_#{id}", source: "simplefin")
    end
end
