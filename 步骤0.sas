options validvarname=upcase;
ods graphics on;

%let root = /home/u64503303;
libname out "&root/Kaplan-Meier";


%macro import_xpt(file=, out=);
    libname xin xport "&file" access=readonly;

    proc contents data=xin._all_ out=_xpt_contents noprint;
    run;

    proc sql noprint;
        select distinct memname into :_mem trimmed
        from _xpt_contents;
    quit;

    data &out;
        set xin.&_mem;
    run;

    libname xin clear;
%mend;


%macro read_mort(datfile=, out=);
    data &out;
        infile "&datfile" lrecl=61 pad missover;

        input
            SEQN          1-6
            ELIGSTAT      15
            MORTSTAT      16
            UCOD_LEADING  $17-19
            DIABETES      20
            HYPERTEN      21
            PERMTH_INT    43-45
            PERMTH_EXM    46-48
        ;

        death = (MORTSTAT = 1);

        if not missing(PERMTH_EXM) then follow_month = PERMTH_EXM;
        else follow_month = PERMTH_INT;
    run;
%mend;


%macro process_cycle(
    year=,
    cycle=,
    folder=,
    demo_file=,
    hdl_file=,
    tchol_file=,
    trigly_file=,
    rx_file=,
    mort_file=
);

    %import_xpt(file=&root/&folder/&demo_file,   out=demo_&year);
    %import_xpt(file=&root/&folder/&hdl_file,    out=hdl_&year);
    %import_xpt(file=&root/&folder/&tchol_file,  out=tchol_&year);
    %import_xpt(file=&root/&folder/&trigly_file, out=trigly_&year);
    %import_xpt(file=&root/&folder/&rx_file,     out=rx_&year);

    %read_mort(
        datfile=&root/&folder/&mort_file,
        out=mort_&year
    );

    /* RXQ_RX 是一人多药记录，必须先聚合到 SEQN 层面 */
    data rx_flag_&year;
        set rx_&year;

        length drug $200;
        drug = upcase(coalescec(RXDDRUG, ""));

        rx_any_row = (RXDUSE = 1 or not missing(RXDDRUG));

        lipid_med_row =
            index(drug, "STATIN") > 0 or
            index(drug, "ATORVASTATIN") > 0 or
            index(drug, "SIMVASTATIN") > 0 or
            index(drug, "ROSUVASTATIN") > 0 or
            index(drug, "PRAVASTATIN") > 0 or
            index(drug, "LOVASTATIN") > 0 or
            index(drug, "FLUVASTATIN") > 0 or
            index(drug, "PITAVASTATIN") > 0 or
            index(drug, "EZETIMIBE") > 0 or
            index(drug, "FENOFIBRATE") > 0 or
            index(drug, "GEMFIBROZIL") > 0 or
            index(drug, "NIACIN") > 0;
    run;

    proc sql;
        create table rxagg_&year as
        select
            SEQN,
            max(rx_any_row) as rx_any,
            max(lipid_med_row) as lipid_med,
            max(RXDCOUNT) as rx_count
        from rx_flag_&year
        group by SEQN;
    quit;

    proc sort data=demo_&year;   by SEQN; run;
    proc sort data=mort_&year;   by SEQN; run;
    proc sort data=hdl_&year;    by SEQN; run;
    proc sort data=tchol_&year;  by SEQN; run;
    proc sort data=trigly_&year; by SEQN; run;
    proc sort data=rxagg_&year;  by SEQN; run;

    /* 以 SEQN 为主键横向合并 */
    data merged_&year;
        merge
            demo_&year   (in=in_demo)
            mort_&year   (in=in_mort)
            hdl_&year
            tchol_&year
            trigly_&year
            rxagg_&year
        ;
        by SEQN;

        if in_demo;

        length cycle $9;
        cycle = "&cycle";
        cycle_start = &year;

        if missing(rx_any) then rx_any = 0;
        if missing(lipid_med) then lipid_med = 0;
        if missing(rx_count) then rx_count = 0;

        /* 连续变量离散化：正常/异常 */
        if not missing(LBXTC) then tc_abn = (LBXTC >= 200);

        if not missing(LBDHDD) and RIAGENDR = 1 then hdl_abn = (LBDHDD < 40);
        else if not missing(LBDHDD) and RIAGENDR = 2 then hdl_abn = (LBDHDD < 50);

        if not missing(LBXTR) then tg_abn = (LBXTR >= 150);

        if not missing(LBDLDL) then ldl_abn = (LBDLDL >= 130);

        /* 4 个 2-year 周期合并为 8-year 权重 */
        if not missing(WTMEC2YR) then WTMEC8YR = WTMEC2YR / 4;
        if not missing(WTSAF2YR) then WTSAF8YR = WTSAF2YR / 4;

        label
            death        = "All-cause mortality indicator"
            follow_month = "Follow-up months"
            tc_abn       = "Total cholesterol abnormal: >=200 mg/dL"
            hdl_abn      = "HDL abnormal: male <40, female <50 mg/dL"
            tg_abn       = "Triglyceride abnormal: >=150 mg/dL"
            ldl_abn      = "LDL abnormal: >=130 mg/dL"
            lipid_med    = "Lipid-lowering medication flag"
            WTMEC8YR     = "8-year MEC weight"
            WTSAF8YR     = "8-year fasting subsample weight"
        ;
    run;

    /* 剔除关键变量缺失 */
    data out.final_data_&year;
        set merged_&year;

        if RIDAGEYR < 20 then delete;

        if ELIGSTAT ne 1 then delete;
        if missing(MORTSTAT) then delete;
        if missing(follow_month) then delete;

        if missing(SEQN) then delete;
        if missing(RIAGENDR) then delete;
        if missing(RIDAGEYR) then delete;
        if missing(LBXTC) then delete;
        if missing(LBDHDD) then delete;
        if missing(LBXTR) then delete;

        /* 如果 LDL 不是你的关键变量，可注释掉下一行 */
        if missing(LBDLDL) then delete;
    run;

%mend;


/* ---------- 4. 分别处理四个周期 ---------- */

%process_cycle(
    year=2011,
    cycle=2011-2012,
    folder=2011-2012,
    demo_file=2011_DEMO_G.xpt,
    hdl_file=2011_HDL_G.xpt,
    tchol_file=2011_TCHOL_G.xpt,
    trigly_file=2011_TRIGLY_G.xpt,
    rx_file=2011_RXQ_RX_G.xpt,
    mort_file=2011_NHANES_2011_2012_MORT_2019_PUBLIC.dat
);

%process_cycle(
    year=2013,
    cycle=2013-2014,
    folder=2013-2014,
    demo_file=2013_DEMO_H.xpt,
    hdl_file=2013_HDL_H.xpt,
    tchol_file=2013_TCHOL_H.xpt,
    trigly_file=2013_TRIGLY_H.xpt,
    rx_file=2013_RXQ_RX_H.xpt,
    mort_file=2013_NHANES_2013_2014_MORT_2019_PUBLIC.dat
);

%process_cycle(
    year=2015,
    cycle=2015-2016,
    folder=2015-2016,
    demo_file=2015_DEMO_I.xpt,
    hdl_file=2015_HDL_I.xpt,
    tchol_file=2015_TCHOL_I.xpt,
    trigly_file=2015_TRIGLY_I.xpt,
    rx_file=2015_RXQ_RX_I.xpt,
    mort_file=2015_NHANES_2015_2016_MORT_2019_PUBLIC.dat
);

%process_cycle(
    year=2017,
    cycle=2017-2018,
    folder=2017-2018,
    demo_file=2017_DEMO_J.xpt,
    hdl_file=2017_HDL_J.xpt,
    tchol_file=2017_TCHOL_J.xpt,
    trigly_file=2017_TRIGLY_J.xpt,
    rx_file=2017_RXQ_RX_J.xpt,
    mort_file=2017_NHANES_2017_2018_MORT_2019_PUBLIC.dat
);


/* ---------- 5. 四个周期纵向合并 ---------- */
data out.nhanes_2011_2018_analysis;
    set
        out.final_data_2011
        out.final_data_2013
        out.final_data_2015
        out.final_data_2017
    ;
run;


/* ---------- 6. 检查步骤 0 的处理结果 ---------- */
proc contents data=out.nhanes_2011_2018_analysis varnum;
run;

proc freq data=out.nhanes_2011_2018_analysis;
    tables cycle death tc_abn hdl_abn tg_abn ldl_abn lipid_med / missing;
run;

proc means data=out.nhanes_2011_2018_analysis n nmiss mean std min p25 median p75 max;
    var RIDAGEYR LBXTC LBDHDD LBXTR LBDLDL follow_month;
run;

ods graphics off;
