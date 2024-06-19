-- Total customers and orders in each month 
SELECT 
  format_datetime('%Y-%m',t1.created_at) as order_time,
  count(distinct t1.user_id) as total_customer,
  count(t1.order_id) as total_order
from bigquery-public-data.thelook_ecommerce.orders as t1
Join bigquery-public-data.thelook_ecommerce.order_items as t2 
on t1.order_id=t2.order_id
Where t1.status='Complete' 
group by format_datetime('%Y-%m',t1.created_at)
order by order_time
LIMIT 1000
  
--Average revenue per order and total revenue each month 
select 
  format_datetime('%Y-%m', created_at) as order_time,  
  round(sum(sale_price)/ count(order_id),2) as avg_revenue,
  round(sum(sale_price),2) as total_revenue 
from bigquery-public-data.thelook_ecommerce.order_items
where status='Complete'
group by format_datetime('%Y-%m',created_at)
order by order_time

-- Total revenue and revenue growth rate by quarter and year

with calculation as(
select 
  format_datetime('%Y-%m', created_at) as order_time, 
  format_datetime('%Q', created_at) as quarter_time, 
  format_datetime('%Y', created_at) as year,
  round(sum(sale_price)/ count(order_id),2) as avg_revenue,
  round(sum(sale_price),2) as total_revenue,
from bigquery-public-data.thelook_ecommerce.order_items
where status='Complete'
group by format_datetime('%Y-%m',created_at), format_datetime('%Q', created_at), format_datetime('%Y', created_at)
order by quarter_time, year
), previous_revenue as(
select
  quarter_time,
  year,
  round(sum(total_revenue),2) as total_revenue,
  lag(round(sum(total_revenue),2)) over (partition by quarter_time order by quarter_time, year) as previous_revenue  
from calculation
group by quarter_time, year
order by quarter_time, year
)
select 
  quarter_time, year, previous_revenue.total_revenue,
  round(((previous_revenue.total_revenue - previous_revenue.previous_revenue)/previous_revenue.total_revenue) * 100,2) as growth_rate
from previous_revenue
order by quarter_time, year

--Oldest and Youngest customer by gender from 1/2019 to 4/2022
  --Youngest: 12 years old (1010 in total with more F than M)
  --Oldest:70 years old (933 in total with F and M similar)

With age_calculation as(
select 
  first_name,
  last_name,
  gender,
  age,
  "youngest" as tag
from (
select 
  first_name,
  last_name,
  gender,
  age,
  (select min(age) from bigquery-public-data.thelook_ecommerce.users) as min_age
from bigquery-public-data.thelook_ecommerce.users
where format_datetime('%Y-%m', created_at) between '2019-01' and '2022-04'
) as min_age_table
where age = min_age

UNION ALL

select 
  first_name,
  last_name,
  gender,
  age,
  "oldest" as tag
from (
select 
  first_name,
  last_name,
  gender,
  age,
  (select max(age) from bigquery-public-data.thelook_ecommerce.users) as max_age
from bigquery-public-data.thelook_ecommerce.users
where format_datetime('%Y-%m', created_at) between '2019-01' and '2022-04'
) as max_age_table
where age = max_age

UNION ALL

select 
  first_name,
  last_name,
  gender,
  age,
  "" as tag
from bigquery-public-data.thelook_ecommerce.users
where age <> 12 and age <> 70
)
select age, tag, gender, count(tag) as total
from age_calculation
group by age, tag, gender
order by age, gender


-- Top 5 product generating highest revenue for each month
with product_revenue as(
SELECT 
  format_datetime('%Y-%m', oi.created_at) as yearmonth, 
  oi.product_id as product_id, 
  pr.name as product_name,
  round(sum(pr.cost), 2) as cost,
  round(sum(oi.sale_price),2) as sales,
  round(sum(oi.sale_price - pr.cost),2) as profit,
FROM `bigquery-public-data.thelook_ecommerce.order_items` as oi
join bigquery-public-data.thelook_ecommerce.products as pr
on oi.product_id = pr.id
where oi.status='Complete'
group by format_datetime('%Y-%m', oi.created_at), oi.product_id, pr.name
), ranking as(
select *,
  dense_rank() over (partition by yearmonth order by profit desc) as rank_product
from product_revenue
)
select distinct
  ranking.yearmonth,
  ranking.product_id,
  ranking. product_name,
  ranking.cost,
  ranking.sales,
  ranking. profit,
  ini.product_category,
  ranking.rank_product
from ranking
join bigquery-public-data.thelook_ecommerce.inventory_items as ini
on ranking.product_id = ini. product_id
where ranking.rank_product<=5
order by ranking.yearmonth, ranking.rank_product

--Daily revenune by category in the last three months
select 
  format_datetime('%Y-%m-%d', oi.created_at) as dates,
  pr.category as product_category,
  round(sum(sale_price),2) as revenue
from bigquery-public-data.thelook_ecommerce.products as pr
join bigquery-public-data.thelook_ecommerce.order_items as oi
on pr.id = oi.product_id
where date_diff(cast(format_datetime('%Y-%m-%d', oi.created_at) as date), cast('2022-04-15' as date), month) =3
group by format_datetime('%Y-%m-%d', oi.created_at), pr.category
order by dates

--- COHORT ANALYSIS
With a as
(Select user_id, amount, FORMAT_DATE('%Y-%m', first_purchase_date) as cohort_month,
created_at,
(Extract(year from created_at) - extract(year from first_purchase_date))*12 
  + Extract(MONTH from created_at) - extract(MONTH from first_purchase_date) +1
  as index
from 
(
Select user_id, 
round(sale_price,2) as amount,
Min(created_at) OVER (PARTITION BY user_id) as first_purchase_date,
created_at
from bigquery-public-data.thelook_ecommerce.order_items 
) as b),
cohort_data as
(
Select cohort_month, 
index,
COUNT(DISTINCT user_id) as user_count,
round(SUM(amount),2) as revenue
from a
Group by cohort_month, index
ORDER BY INDEX
),
--CUSTOMER COHORT-- 
Customer_cohort as
(
Select 
cohort_month,
Sum(case when index=1 then user_count else 0 end) as m1,
Sum(case when index=2 then user_count else 0 end) as m2,
Sum(case when index=3 then user_count else 0 end) as m3,
Sum(case when index=4 then user_count else 0 end) as m4
from cohort_data
Group by cohort_month
Order by cohort_month
),
--RETENTION COHORT--
retention_cohort as
(
Select cohort_month,
round(100.00* m1/m1,2) || '%' as m1,
round(100.00* m2/m1,2) || '%' as m2,
round(100.00* m3/m1,2) || '%' as m3,
round(100.00* m4/m1,2) || '%' as m4
from customer_cohort
)
--CHURN COHORT--
Select cohort_month,
(100.00 - round(100.00* m1/m1,2)) || '%' as m1,
(100.00 - round(100.00* m2/m1,2)) || '%' as m2,
(100.00 - round(100.00* m3/m1,2)) || '%' as m3,
(100.00 - round(100.00* m4/m1,2))|| '%' as m4
from customer_cohort


--Table with summary information for visualization
SELECT 
  format_datetime('%Y-%m',t1.created_at) as order_time,
  us.gender as gender,
  count(distinct t1.user_id) as total_customer,
  count(t1.order_id) as total_order,
  round(sum(sale_price)/ count(t1.order_id),2) as avg_revenue,
  round(sum(sale_price),2) as total_revenue
from bigquery-public-data.thelook_ecommerce.orders as t1
Join bigquery-public-data.thelook_ecommerce.order_items as t2 
on t1.order_id=t2.order_id
join bigquery-public-data.thelook_ecommerce.users as us
on us.id = t1.user_id
Where t1.status='Complete' and 
t2.delivered_at BETWEEN '2019-01-01 00:00:00' AND '2022-05-01 00:00:00' 
group by format_datetime('%Y-%m',t1.created_at), us.gender
order by order_time, gender
