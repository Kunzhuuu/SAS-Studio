options validvarname=upcase;
ods graphics on;

%let root = /home/u64503303;
libname out "&root/Kaplan-Meier";


/* 1. 构造以“年”为单位的随访时间 */
data life_2011_2018;
    set out.nhanes_2011_2018_analysis;

    follow_year = follow_month / 12;

    label
        follow_year = "Follow-up time in years"
        death       = "All-cause mortality indicator"
        cycle       = "NHANES cycle";
run;


/* 2. 查看总体随访时间范围 */
proc means data=life_2011_2018 n min p25 median p75 max;
    var follow_year follow_month;
run;


/* 3. 全队列寿命表法：1 年为区间 */
proc lifetest data=life_2011_2018
    method=life
    intervals=0 to 9 by 1
    plots=(survival hazard);
    
    time follow_year * death(0);

    ods output LifeTableEstimates = out.life_table_2011_2018;
run;


/* 4. 按 NHANES 周期分别计算寿命表，便于四个周期对比 */
proc lifetest data=life_2011_2018
    method=life
    intervals=0 to 9 by 1
    plots=survival;
    
    time follow_year * death(0);
    strata cycle;

    ods output LifeTableEstimates = out.life_table_by_cycle;
run;

ods graphics off;


/* 5. 查看结果 */
proc print data=out.life_table_2011_2018 label;
run;

proc print data=out.life_table_by_cycle label;
run;


/* 6. 导出 Excel，方便论文制表 */
proc export data=out.life_table_2011_2018
    outfile="&root/Kaplan-Meier/life_table_2011_2018.xlsx"
    dbms=xlsx
    replace;
run;

proc export data=out.life_table_by_cycle
    outfile="&root/Kaplan-Meier/life_table_by_cycle.xlsx"
    dbms=xlsx
    replace;
run;
