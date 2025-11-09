-- Supabase Database Schema for Muscle AI App
-- Run this in your Supabase SQL editor

-- Create profiles table
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  username TEXT UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security on profiles table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;

-- Create policies for profiles table
CREATE POLICY "Users can view their own profile" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Create function to handle user profile creation on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, avatar_url, username)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture', ''),
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to automatically create profile on user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update updated_at on profile changes
CREATE OR REPLACE TRIGGER on_profile_updated
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Optional: Create analysis_history table for storing user's muscle analysis data
CREATE TABLE IF NOT EXISTS public.analysis_history (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  analysis_data JSONB NOT NULL,
  overall_score INTEGER,
  image_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on analysis_history
ALTER TABLE public.analysis_history ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own analysis history" ON public.analysis_history;
DROP POLICY IF EXISTS "Users can insert their own analysis" ON public.analysis_history;
DROP POLICY IF EXISTS "Users can update their own analysis" ON public.analysis_history;
DROP POLICY IF EXISTS "Users can delete their own analysis" ON public.analysis_history;

-- Create policies for analysis_history
CREATE POLICY "Users can view their own analysis history" ON public.analysis_history
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own analysis" ON public.analysis_history
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own analysis" ON public.analysis_history
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own analysis" ON public.analysis_history
  FOR DELETE USING (auth.uid() = user_id);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles(username);
CREATE INDEX IF NOT EXISTS idx_analysis_history_user_id ON public.analysis_history(user_id);
CREATE INDEX IF NOT EXISTS idx_analysis_history_created_at ON public.analysis_history(created_at DESC);

-- =====================================================
-- SUBSCRIPTION SYSTEM SCHEMA
-- =====================================================

-- Create subscription_plans table
CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  plan_name TEXT NOT NULL UNIQUE,
  plan_price_usd DECIMAL(10, 2) NOT NULL,
  monthly_analyses_limit INTEGER NOT NULL,
  razorpay_plan_id TEXT UNIQUE,
  description TEXT,
  features JSONB DEFAULT '[]'::jsonb,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on subscription_plans
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if exists
DROP POLICY IF EXISTS "Anyone can view active subscription plans" ON public.subscription_plans;

-- Policy: Anyone can view active plans
CREATE POLICY "Anyone can view active subscription plans" ON public.subscription_plans
  FOR SELECT USING (is_active = true);

-- Insert default subscription plans
INSERT INTO public.subscription_plans (plan_name, plan_price_usd, monthly_analyses_limit, description, features)
VALUES 
  ('Basic', 4.00, 5, 'Perfect for beginners starting their fitness journey', 
   '["5 AI body analyses per month", "Workout recommendations", "Progress tracking", "Basic muscle insights"]'::jsonb),
  ('Pro', 7.00, 20, 'Ideal for fitness enthusiasts tracking progress regularly',
   '["20 AI body analyses per month", "Advanced workout plans", "Detailed progress tracking", "Muscle group analysis", "Priority support"]'::jsonb),
  ('VIP', 14.00, 50, 'Ultimate plan for serious athletes and bodybuilders',
   '["50 AI body analyses per month", "Premium workout plans", "Advanced analytics", "Detailed muscle insights", "Comparison tools", "Priority support", "Early access to features"]'::jsonb)
ON CONFLICT (plan_name) DO NOTHING;

-- Create user_subscriptions table
CREATE TABLE IF NOT EXISTS public.user_subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  plan_id UUID REFERENCES public.subscription_plans(id) NOT NULL,
  subscription_status TEXT NOT NULL CHECK (subscription_status IN ('pending', 'active', 'cancelled', 'expired', 'past_due', 'paused')),
  razorpay_subscription_id TEXT UNIQUE,
  razorpay_customer_id TEXT,
  current_billing_cycle_start TIMESTAMP WITH TIME ZONE,
  current_billing_cycle_end TIMESTAMP WITH TIME ZONE,
  analyses_used_this_month INTEGER DEFAULT 0 CHECK (analyses_used_this_month >= 0),
  subscription_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  subscription_end_date TIMESTAMP WITH TIME ZONE,
  auto_renewal_enabled BOOLEAN DEFAULT true,
  cancelled_at TIMESTAMP WITH TIME ZONE,
  pause_start_date TIMESTAMP WITH TIME ZONE,
  pause_end_date TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create partial unique index to ensure only one active subscription per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_active_subscription 
ON public.user_subscriptions(user_id) 
WHERE subscription_status = 'active';

-- Enable RLS on user_subscriptions
ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own subscriptions" ON public.user_subscriptions;
DROP POLICY IF EXISTS "Users can insert their own subscriptions" ON public.user_subscriptions;
DROP POLICY IF EXISTS "Service role can manage all subscriptions" ON public.user_subscriptions;

-- Policies for user_subscriptions
CREATE POLICY "Users can view their own subscriptions" ON public.user_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own subscriptions" ON public.user_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role can manage all subscriptions" ON public.user_subscriptions
  FOR ALL USING (auth.jwt()->>'role' = 'service_role');

-- Create payment_transactions table
CREATE TABLE IF NOT EXISTS public.payment_transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  subscription_id UUID REFERENCES public.user_subscriptions(id) ON DELETE SET NULL,
  razorpay_payment_id TEXT UNIQUE,
  razorpay_order_id TEXT,
  razorpay_signature TEXT,
  amount_paid_usd DECIMAL(10, 2) NOT NULL,
  currency TEXT DEFAULT 'USD',
  payment_status TEXT NOT NULL CHECK (payment_status IN ('pending', 'authorized', 'captured', 'failed', 'refunded')),
  payment_method TEXT,
  error_code TEXT,
  error_description TEXT,
  transaction_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on payment_transactions
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own transactions" ON public.payment_transactions;
DROP POLICY IF EXISTS "Service role can manage all transactions" ON public.payment_transactions;

-- Policies for payment_transactions
CREATE POLICY "Users can view their own transactions" ON public.payment_transactions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage all transactions" ON public.payment_transactions
  FOR ALL USING (auth.jwt()->>'role' = 'service_role');

-- Create usage_tracking table
CREATE TABLE IF NOT EXISTS public.usage_tracking (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  subscription_id UUID REFERENCES public.user_subscriptions(id) ON DELETE SET NULL,
  analysis_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  analysis_type TEXT DEFAULT 'body_analysis',
  analysis_result_id UUID REFERENCES public.analysis_history(id) ON DELETE SET NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on usage_tracking
ALTER TABLE public.usage_tracking ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own usage" ON public.usage_tracking;
DROP POLICY IF EXISTS "Users can insert their own usage" ON public.usage_tracking;
DROP POLICY IF EXISTS "Service role can manage all usage" ON public.usage_tracking;

-- Policies for usage_tracking
CREATE POLICY "Users can view their own usage" ON public.usage_tracking
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own usage" ON public.usage_tracking
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role can manage all usage" ON public.usage_tracking
  FOR ALL USING (auth.jwt()->>'role' = 'service_role');

-- Create indexes for subscription system
CREATE INDEX IF NOT EXISTS idx_subscription_plans_name ON public.subscription_plans(plan_name);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON public.user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status ON public.user_subscriptions(subscription_status);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_razorpay_id ON public.user_subscriptions(razorpay_subscription_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_user_id ON public.payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_subscription_id ON public.payment_transactions(subscription_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_razorpay_payment_id ON public.payment_transactions(razorpay_payment_id);
CREATE INDEX IF NOT EXISTS idx_usage_tracking_user_id ON public.usage_tracking(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_tracking_date ON public.usage_tracking(analysis_date DESC);

-- Create trigger for subscription_plans updated_at
CREATE TRIGGER on_subscription_plans_updated
  BEFORE UPDATE ON public.subscription_plans
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Create trigger for user_subscriptions updated_at
CREATE TRIGGER on_user_subscriptions_updated
  BEFORE UPDATE ON public.user_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Function to check if user can perform analysis
CREATE OR REPLACE FUNCTION public.can_user_analyze()
RETURNS TABLE (
  can_analyze BOOLEAN,
  analyses_remaining INTEGER,
  subscription_status TEXT,
  plan_name TEXT
) AS $$
DECLARE
  v_user_id UUID;
  v_subscription RECORD;
  v_plan RECORD;
BEGIN
  v_user_id := auth.uid();
  
  -- Get active subscription
  SELECT * INTO v_subscription
  FROM public.user_subscriptions us
  WHERE us.user_id = v_user_id 
    AND us.subscription_status = 'active'
    AND us.current_billing_cycle_end > NOW()
  ORDER BY us.created_at DESC
  LIMIT 1;
  
  -- If no active subscription, return false
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 0, 'none'::TEXT, 'none'::TEXT;
    RETURN;
  END IF;
  
  -- Get plan details
  SELECT * INTO v_plan
  FROM public.subscription_plans sp
  WHERE sp.id = v_subscription.plan_id;
  
  -- Check if user has remaining analyses
  IF v_subscription.analyses_used_this_month < v_plan.monthly_analyses_limit THEN
    RETURN QUERY SELECT 
      true,
      v_plan.monthly_analyses_limit - v_subscription.analyses_used_this_month,
      v_subscription.subscription_status,
      v_plan.plan_name;
  ELSE
    RETURN QUERY SELECT 
      false,
      0,
      v_subscription.subscription_status,
      v_plan.plan_name;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment usage counter
CREATE OR REPLACE FUNCTION public.increment_usage_counter(
  p_analysis_result_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_subscription RECORD;
  v_result JSONB;
BEGIN
  v_user_id := auth.uid();
  
  -- Get active subscription
  SELECT * INTO v_subscription
  FROM public.user_subscriptions us
  WHERE us.user_id = v_user_id 
    AND us.subscription_status = 'active'
    AND us.current_billing_cycle_end > NOW()
  ORDER BY us.created_at DESC
  LIMIT 1;
  
  -- If no active subscription, return error
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No active subscription found'
    );
  END IF;
  
  -- Increment counter
  UPDATE public.user_subscriptions
  SET analyses_used_this_month = analyses_used_this_month + 1,
      updated_at = NOW()
  WHERE id = v_subscription.id;
  
  -- Track usage
  INSERT INTO public.usage_tracking (
    user_id,
    subscription_id,
    analysis_type,
    analysis_result_id
  ) VALUES (
    v_user_id,
    v_subscription.id,
    'body_analysis',
    p_analysis_result_id
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'analyses_used', v_subscription.analyses_used_this_month + 1
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to reset monthly usage counters (run via cron job)
CREATE OR REPLACE FUNCTION public.reset_monthly_usage_counters()
RETURNS void AS $$
BEGIN
  UPDATE public.user_subscriptions
  SET analyses_used_this_month = 0,
      updated_at = NOW()
  WHERE subscription_status = 'active'
    AND current_billing_cycle_end < NOW()
    AND current_billing_cycle_end > NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's subscription details
CREATE OR REPLACE FUNCTION public.get_user_subscription_details()
RETURNS TABLE (
  subscription_id UUID,
  plan_name TEXT,
  plan_price DECIMAL,
  subscription_status TEXT,
  analyses_used INTEGER,
  analyses_limit INTEGER,
  analyses_remaining INTEGER,
  cycle_start TIMESTAMP WITH TIME ZONE,
  cycle_end TIMESTAMP WITH TIME ZONE,
  auto_renewal BOOLEAN,
  razorpay_subscription_id TEXT
) AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  RETURN QUERY
  SELECT 
    us.id,
    sp.plan_name,
    sp.plan_price_usd,
    us.subscription_status,
    us.analyses_used_this_month,
    sp.monthly_analyses_limit,
    sp.monthly_analyses_limit - us.analyses_used_this_month,
    us.current_billing_cycle_start,
    us.current_billing_cycle_end,
    us.auto_renewal_enabled,
    us.razorpay_subscription_id
  FROM public.user_subscriptions us
  JOIN public.subscription_plans sp ON us.plan_id = sp.id
  WHERE us.user_id = v_user_id
    AND us.subscription_status = 'active'
  ORDER BY us.created_at DESC
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
