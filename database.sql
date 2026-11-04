
-- =====================================================
-- نظام محاسبة النقل - الجزائر
-- PostgreSQL / Supabase
-- SCF - DZD
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. إعدادات المؤسسة
CREATE TABLE IF NOT EXISTS company_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name TEXT NOT NULL DEFAULT 'بوهافس لاردج',
    legal_form TEXT DEFAULT 'Personne physique',
    country TEXT DEFAULT 'Algeria',
    currency VARCHAR(3) DEFAULT 'DZD',
    accounting_standard TEXT DEFAULT 'SCF',
    language TEXT DEFAULT 'ar',
    secondary_language TEXT DEFAULT 'fr',
    fiscal_year_start DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. شجرة الحسابات
CREATE TABLE IF NOT EXISTS accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(20) NOT NULL UNIQUE,
    parent_code VARCHAR(20) REFERENCES accounts(code),
    account_type VARCHAR(40) NOT NULL,
    reconcilable BOOLEAN DEFAULT FALSE,
    name_ar TEXT NOT NULL,
    name_fr TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    sequence INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_accounts_parent
ON accounts(parent_code);

-- 3. العملاء والموردون
CREATE TABLE IF NOT EXISTS partners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_type VARCHAR(20) NOT NULL
      CHECK (partner_type IN ('customer','supplier','both')),
    name TEXT NOT NULL,
    tax_id TEXT,
    address TEXT,
    phone TEXT,
    email TEXT,
    opening_balance NUMERIC(16,2) DEFAULT 0,
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. السائقون
CREATE TABLE IF NOT EXISTS drivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    phone TEXT,
    identity_number TEXT,
    hire_date DATE,
    base_salary NUMERIC(16,2) DEFAULT 0,
    trip_bonus NUMERIC(16,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. الشاحنات والمقطورات
CREATE TABLE IF NOT EXISTS vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    registration_number VARCHAR(30) NOT NULL UNIQUE,
    vehicle_type VARCHAR(20) NOT NULL
      CHECK (vehicle_type IN ('truck','trailer')),
    brand TEXT,
    model TEXT,
    model_year INTEGER,
    chassis_number TEXT,
    is_company_owned BOOLEAN DEFAULT TRUE,
    purchase_date DATE,
    purchase_cost NUMERIC(16,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. الرحلات
CREATE TABLE IF NOT EXISTS trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_reference VARCHAR(60) UNIQUE,
    trip_date DATE NOT NULL DEFAULT CURRENT_DATE,
    customer_id UUID REFERENCES partners(id),
    driver_id UUID REFERENCES drivers(id),
    truck_id UUID REFERENCES vehicles(id),
    trailer_id UUID REFERENCES vehicles(id),
    loading_location TEXT,
    unloading_location TEXT,
    product_name TEXT,
    road_sheet_number TEXT,
    loaded_quantity NUMERIC(14,3) DEFAULT 0,
    unloaded_quantity NUMERIC(14,3) DEFAULT 0,
    price NUMERIC(16,2) NOT NULL DEFAULT 0,
    revenue NUMERIC(16,2)
      GENERATED ALWAYS AS (unloaded_quantity * price) STORED,
    departure_at TIMESTAMPTZ,
    arrival_at TIMESTAMPTZ,
    status VARCHAR(20) DEFAULT 'planned'
      CHECK (status IN ('planned','in_progress','completed','cancelled')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trips_date ON trips(trip_date);
CREATE INDEX IF NOT EXISTS idx_trips_driver ON trips(driver_id);
CREATE INDEX IF NOT EXISTS idx_trips_customer ON trips(customer_id);

-- 7. مصاريف المؤسسة
CREATE TABLE IF NOT EXISTS expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_date DATE DEFAULT CURRENT_DATE,
    vehicle_id UUID REFERENCES vehicles(id),
    driver_id UUID REFERENCES drivers(id),
    trip_id UUID REFERENCES trips(id),
    expense_type VARCHAR(30) NOT NULL
      CHECK (expense_type IN (
        'fuel','maintenance','tires','parts',
        'road','insurance','wages','other'
      )),
    description TEXT NOT NULL,
    amount NUMERIC(16,2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(20) DEFAULT 'cash'
      CHECK (payment_method IN (
        'cash','bank','driver_custody','other'
      )),
    document_reference TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_expenses_date
ON expenses(expense_date);

-- 8. عهد السائقين
CREATE TABLE IF NOT EXISTS driver_custodies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES drivers(id),
    custody_date DATE DEFAULT CURRENT_DATE,
    amount_given NUMERIC(16,2) NOT NULL CHECK (amount_given > 0),
    purpose TEXT,
    payment_method VARCHAR(20) DEFAULT 'cash',
    reference TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- تسوية العهد
CREATE TABLE IF NOT EXISTS custody_settlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    custody_id UUID NOT NULL REFERENCES driver_custodies(id),
    settlement_date DATE DEFAULT CURRENT_DATE,
    expense_amount NUMERIC(16,2) DEFAULT 0,
    returned_amount NUMERIC(16,2) DEFAULT 0,
    description TEXT,
    document_reference TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (expense_amount >= 0),
    CHECK (returned_amount >= 0)
);

-- 9. أجور السائقين
CREATE TABLE IF NOT EXISTS driver_payroll (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES drivers(id),
    payroll_month DATE NOT NULL,
    base_amount NUMERIC(16,2) DEFAULT 0,
    trip_bonus_amount NUMERIC(16,2) DEFAULT 0,
    deductions NUMERIC(16,2) DEFAULT 0,
    paid_amount NUMERIC(16,2) DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(driver_id, payroll_month)
);

-- تسبيقات السائقين
CREATE TABLE IF NOT EXISTS driver_advances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES drivers(id),
    advance_date DATE DEFAULT CURRENT_DATE,
    amount NUMERIC(16,2) NOT NULL CHECK (amount > 0),
    deducted_from_payroll BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. فواتير العملاء
CREATE TABLE IF NOT EXISTS invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_number VARCHAR(60) NOT NULL UNIQUE,
    customer_id UUID NOT NULL REFERENCES partners(id),
    invoice_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    subtotal NUMERIC(16,2) DEFAULT 0,
    tax_amount NUMERIC(16,2) DEFAULT 0,
    total_amount NUMERIC(16,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'draft'
      CHECK (status IN (
        'draft','issued','partially_paid','paid','cancelled'
      )),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ربط الفواتير بالرحلات
CREATE TABLE IF NOT EXISTS invoice_trips (
    invoice_id UUID REFERENCES invoices(id) ON DELETE CASCADE,
    trip_id UUID REFERENCES trips(id),
    line_amount NUMERIC(16,2) NOT NULL,
    PRIMARY KEY(invoice_id, trip_id)
);

-- تحصيلات العملاء
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES partners(id),
    invoice_id UUID REFERENCES invoices(id),
    payment_date DATE DEFAULT CURRENT_DATE,
    amount NUMERIC(16,2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(20) DEFAULT 'bank'
      CHECK (payment_method IN ('cash','bank','other')),
    reference TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. دفتر اليومية
CREATE TABLE IF NOT EXISTS journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_number VARCHAR(60) UNIQUE,
    entry_date DATE DEFAULT CURRENT_DATE,
    journal_type VARCHAR(20) DEFAULT 'general'
      CHECK (journal_type IN (
        'general','sales','purchases','cash','bank','payroll'
      )),
    description TEXT NOT NULL,
    source_type TEXT,
    source_id UUID,
    status VARCHAR(20) DEFAULT 'draft'
      CHECK (status IN ('draft','posted','cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- تفاصيل القيود المحاسبية
CREATE TABLE IF NOT EXISTS journal_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_entry_id UUID NOT NULL
      REFERENCES journal_entries(id) ON DELETE CASCADE,
    line_number INTEGER NOT NULL,
    account_code VARCHAR(20) NOT NULL REFERENCES accounts(code),
    partner_id UUID REFERENCES partners(id),
    driver_id UUID REFERENCES drivers(id),
    vehicle_id UUID REFERENCES vehicles(id),
    description TEXT,
    debit NUMERIC(16,2) DEFAULT 0,
    credit NUMERIC(16,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(journal_entry_id, line_number),
    CHECK (debit >= 0 AND credit >= 0),
    CHECK (
      (debit > 0 AND credit = 0)
      OR
      (credit > 0 AND debit = 0)
    )
);

CREATE INDEX IF NOT EXISTS idx_journal_lines_account
ON journal_lines(account_code);

CREATE INDEX IF NOT EXISTS idx_journal_entries_date
ON journal_entries(entry_date);

-- 12. كشف عهد السائقين
CREATE OR REPLACE VIEW driver_custody_balances AS
WITH custody_totals AS (
    SELECT
      c.id,
      c.driver_id,
      c.amount_given,
      COALESCE(SUM(s.expense_amount),0) AS expenses,
      COALESCE(SUM(s.returned_amount),0) AS returned
    FROM driver_custodies c
    LEFT JOIN custody_settlements s ON s.custody_id = c.id
    GROUP BY c.id, c.driver_id, c.amount_given
)
SELECT
    d.id AS driver_id,
    d.full_name,
    COALESCE(SUM(c.amount_given),0) AS total_custody,
    COALESCE(SUM(c.expenses),0) AS settled_expenses,
    COALESCE(SUM(c.returned),0) AS returned_amount,
    COALESCE(SUM(
      c.amount_given - c.expenses - c.returned
    ),0) AS remaining_balance
FROM drivers d
LEFT JOIN custody_totals c ON c.driver_id = d.id
GROUP BY d.id, d.full_name;

-- 13. كشف الفواتير والتحصيلات
CREATE OR REPLACE VIEW invoice_balances AS
SELECT
    i.id AS invoice_id,
    i.invoice_number,
    i.customer_id,
    i.total_amount,
    COALESCE(SUM(p.amount),0) AS paid_amount,
    i.total_amount - COALESCE(SUM(p.amount),0)
      AS remaining_amount
FROM invoices i
LEFT JOIN payments p ON p.invoice_id = i.id
GROUP BY i.id, i.invoice_number, i.customer_id, i.total_amount;

-- 14. عرض إجمالي إيرادات الرحلات
CREATE OR REPLACE VIEW trip_revenue_summary AS
SELECT
    trip_date,
    customer_id,
    driver_id,
    truck_id,
    SUM(revenue) AS total_revenue,
    COUNT(*) AS trip_count
FROM trips
WHERE status = 'completed'
GROUP BY trip_date, customer_id, driver_id, truck_id;

-- =====================================================
-- نهاية إنشاء قاعدة البيانات الأساسية
-- =====================================================
