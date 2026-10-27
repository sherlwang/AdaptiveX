`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tx_feedback_controller
// Description: Feedback mode policy in the 204.8 MHz Tx control domain.
//   packet_v is a CRC-qualified packet strobe from tx_fb_receiver; consecutive
//   high clocks represent distinct packets. No receiver status/sticky flag gates
//   a subsequent good packet. Mode 0 is P2 BPSK, not an invalid/no-packet code.
//   frame_commit is the SAME edge at which phy_in_request captures requested P/M.
//   tx_frame_done refers to a complete physical frame, excluding valid zero guard.
//   A source adoption starts protection; only ten matching physical frame ends
//   release it, so buffered old-mode frames cannot shorten new-mode residence.
// Revision: 2026/10/22 - Initial version, Verilog-2001 / Vivado 2021.2.
//////////////////////////////////////////////////////////////////////////////////
module tx_feedback_controller #(
    parameter integer WATCHDOG_CLOCKS = 40960,
    parameter integer PROTECT_FRAMES  = 10
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         auto_enable,
    input  wire         link_started,
    input  wire [3:0]   manual_ploy,
    input  wire [1:0]   manual_mod,
    input  wire         frame_commit,
    input  wire         packet_v,
    input  wire [23:0]  packet,
    input  wire         tx_frame_done,
    input  wire [3:0]   tx_frame_ploy,
    input  wire [1:0]   tx_frame_mod,
    output wire [3:0]   requested_ploy,
    output wire [1:0]   requested_mod,
    output reg  [3:0]   applied_mode,
    output wire [3:0]   pending_mode,
    output wire         pending,
    output reg          protect_active,
    output reg  [3:0]   protect_count,
    output reg          timeout,
    output reg          timeout_pulse,
    output reg  [15:0]  watchdog,
    output reg          packet_accept,
    output reg          vote_accept,
    output reg  [2:0]   reject_reason,
    output reg          decision_pulse,
    output reg          adopt_pulse,
    output wire [14:0]  vote_up,
    output wire [14:0]  vote_down,
    output wire [31:0]  candidate_history,
    output reg  [3:0]   candidate_count,
    output reg          recovery_pending,
    output reg          seq_valid,
    output reg  [5:0]   last_seq
);
    // reject_reason describes the latest packet: 0 voted; 1 illegal mode;
    // 2 duplicate/stale sequence; 3 old current mode; 4 protection; 5 pending adoption;
    // 6 manual monitoring; 7 link not started / automatic initialization.
    localparam [2:0] REJ_NONE=3'd0, REJ_MODE=3'd1, REJ_DUP=3'd2;
    localparam [2:0] REJ_CURRENT=3'd3, REJ_PROTECT=3'd4;
    localparam [2:0] REJ_PENDING=3'd5, REJ_MANUAL=3'd6, REJ_START=3'd7;

    reg                 auto_previous;
    reg                 initialize_pending;
    reg                 target_pending;
    reg  [3:0]         target_mode;
    reg  [2:0]         up_count [0:4];
    reg  [2:0]         down_count [0:4];
    reg  [3:0]         history [0:7];
    reg  [2:0]         next_up [0:4];
    reg  [2:0]         next_down [0:4];
    reg                 qualified;
    reg  [2:0]         qualified_group;
    reg  [3:0]         chosen_mode;
    wire [8:0]         observed;
    integer             group_index;
    integer             sequential_index;

    function [3:0] encode_mode;
        input [3:0] p;
        input [1:0] m;
        begin
            if ((p==4'd2 || p==4'd4 || p==4'd8) && m<=2)
                encode_mode = (p==2 ? 4'd0 : p==4 ? 4'd3 : 4'd6) + m;
            else encode_mode = 4'd15;
        end
    endfunction
    function [3:0] mode_p;
        input [3:0] id;
        begin mode_p = id<3 ? 4'd2 : id<6 ? 4'd4 : 4'd8; end
    endfunction
    function [1:0] mode_m;
        input [3:0] id;
        begin mode_m = id<3 ? id[1:0] : id<6 ? id-4'd3 : id-4'd6; end
    endfunction
    function [2:0] mode_group;
        input [3:0] id;
        begin
            case(id)
                4'd0: mode_group=3'd0;
                4'd1,4'd3: mode_group=3'd1;
                4'd2,4'd4,4'd6: mode_group=3'd2;
                4'd5,4'd7: mode_group=3'd3;
                4'd8: mode_group=3'd4;
                default: mode_group=3'd0;
            endcase
        end
    endfunction

    wire [3:0] feedback_current = packet[23:20];
    wire [3:0] feedback_target  = packet[19:16];
    wire [5:0] feedback_seq     = packet[13:8];
    // Half-range modular ordering rejects delayed replays as well as adjacent
    // duplicates, while accepting forward losses and 63 -> 0. The200us watchdog
    // is shorter than32 feedback frame intervals; timeout / automatic re-entry
    // clears this baseline so a remote restart or longer outage can resynchronize.
    wire [5:0] sequence_delta   = feedback_seq-last_seq;
    wire [2:0] current_group    = mode_group(applied_mode);
    wire [2:0] reported_group   = mode_group(feedback_target);
    wire [3:0] physical_mode    = encode_mode(tx_frame_ploy,tx_frame_mod);
    wire [3:0] manual_mode      = encode_mode(manual_ploy,manual_mod);
    wire       automatic_entry = auto_enable && !auto_previous;
    wire       legal_packet    = feedback_current<=8 && feedback_target<=8;
    wire       fresh_packet    = packet_v && legal_packet &&
                                 (!seq_valid || (sequence_delta!=0 && !sequence_delta[5]));
    wire       protection_end  = protect_active && tx_frame_done &&
                                 physical_mode==applied_mode &&
                                 protect_count==PROTECT_FRAMES-1;
    wire       recovery_ready  = recovery_pending &&
                                 (!protect_active || protection_end);
    wire       watchdog_event  = link_started && !fresh_packet && !timeout &&
                                 watchdog==WATCHDOG_CLOCKS-1;
    wire       may_vote        = auto_enable && !automatic_entry &&
                                 !initialize_pending && link_started &&
                                 !protect_active && !target_pending &&
                                 !recovery_pending && feedback_current==applied_mode;
    wire [3:0] requested_mode  = !auto_enable ?
                                (manual_mode<=8 ? manual_mode : 4'd0) :
                                (automatic_entry || initialize_pending || recovery_ready) ?
                                4'd0 : target_pending ? target_mode : applied_mode;
    assign requested_ploy = mode_p(requested_mode);
    assign requested_mod  = mode_m(requested_mode);
    assign pending = target_pending || recovery_pending || initialize_pending || automatic_entry;
    assign pending_mode = (recovery_pending || initialize_pending || automatic_entry) ? 4'd0 : target_mode;

    genvar debug_index;
    generate
        for(debug_index=0;debug_index<5;debug_index=debug_index+1)begin:g_debug_votes
            assign vote_up[3*debug_index +: 3] = up_count[debug_index];
            assign vote_down[3*debug_index +: 3] = down_count[debug_index];
        end
        for(debug_index=0;debug_index<8;debug_index=debug_index+1)begin:g_debug_history
            assign candidate_history[4*debug_index +: 4] = history[debug_index];
        end
    endgenerate

    // Newest real report plus the preceding seven voting-eligible reports.
    // Decode each constant ID independently, avoiding a serial chain of dynamic
    // bit writes. No fabricated default mode enters the candidate set.
    genvar observed_index, observed_history_index;
    generate
        for(observed_index=0;observed_index<9;observed_index=observed_index+1)begin:g_observed
            localparam [3:0] CANDIDATE_ID = observed_index;
            wire [7:0] matches;
            assign matches[0] = feedback_target==CANDIDATE_ID;
            for(observed_history_index=0;observed_history_index<7;
                observed_history_index=observed_history_index+1)begin:g_history
                localparam [3:0] HISTORY_SLOT = observed_history_index;
                assign matches[observed_history_index+1] =
                    candidate_count>HISTORY_SLOT &&
                    history[observed_history_index]==CANDIDATE_ID;
            end
            assign observed[observed_index] = |matches;
        end
    endgenerate

    // Within each throughput group the P-distance ranking is a constant table.
    // The three current-P classes select parallel short priority lists; ties use
    // the smaller ID. This is exactly abs(candidate P-current P), without the
    // former 32-bit integer subtract/compare chain through all nine candidates.
    // As in mode_p(), an out-of-range applied ID follows the P8 ranking.
    wire current_p2 = applied_mode<4'd3;
    wire current_p4 = applied_mode>=4'd3 && applied_mode<4'd6;
    wire [3:0] choice_g0 = observed[0] ? 4'd0 : applied_mode;
    wire [3:0] choice_g1_p2 = observed[1] ? 4'd1 : observed[3] ? 4'd3 : applied_mode;
    wire [3:0] choice_g1_p4_p8 = observed[3] ? 4'd3 : observed[1] ? 4'd1 : applied_mode;
    wire [3:0] choice_g1 = current_p2 ? choice_g1_p2 : choice_g1_p4_p8;
    wire [3:0] choice_g2_p2 = observed[2] ? 4'd2 : observed[4] ? 4'd4 :
                               observed[6] ? 4'd6 : applied_mode;
    wire [3:0] choice_g2_p4 = observed[4] ? 4'd4 : observed[2] ? 4'd2 :
                               observed[6] ? 4'd6 : applied_mode;
    wire [3:0] choice_g2_p8 = observed[6] ? 4'd6 : observed[4] ? 4'd4 :
                               observed[2] ? 4'd2 : applied_mode;
    wire [3:0] choice_g2 = current_p2 ? choice_g2_p2 : current_p4 ? choice_g2_p4 : choice_g2_p8;
    wire [3:0] choice_g3_p2_p4 = observed[5] ? 4'd5 : observed[7] ? 4'd7 : applied_mode;
    wire [3:0] choice_g3_p8 = observed[7] ? 4'd7 : observed[5] ? 4'd5 : applied_mode;
    wire [3:0] choice_g3 = current_p2 || current_p4 ? choice_g3_p2_p4 : choice_g3_p8;
    wire [3:0] choice_g4 = observed[8] ? 4'd8 : applied_mode;
    always @* begin
        case(qualified_group)
            3'd0: chosen_mode=choice_g0;
            3'd1: chosen_mode=choice_g1;
            3'd2: chosen_mode=choice_g2;
            3'd3: chosen_mode=choice_g3;
            3'd4: chosen_mode=choice_g4;
            default: chosen_mode=applied_mode;
        endcase
    end

    // Each absolute throughput threshold has its own consecutive-confirmation
    // count. For example, G4 -> G2 then G0 confirms G2 only, never G0.
    always @* begin
        qualified = 1'b0;
        qualified_group = current_group;
        for(group_index=0;group_index<5;group_index=group_index+1)begin
            next_up[group_index] = 3'd0;
            next_down[group_index] = 3'd0;
            if(group_index>current_group && reported_group>=group_index)
                next_up[group_index] = up_count[group_index]<5 ? up_count[group_index]+1'b1 : 3'd5;
            if(group_index<current_group && reported_group<=group_index)
                next_down[group_index] = down_count[group_index]<5 ? down_count[group_index]+1'b1 : 3'd5;
        end
        // Ascending assignment leaves the highest commonly supported up group.
        for(group_index=0;group_index<5;group_index=group_index+1)begin
            if(group_index>current_group && next_up[group_index]>=5)begin
                qualified=1'b1;
                qualified_group=group_index;
            end
        end
        // Descending assignment leaves the lowest commonly supported down group.
        for(group_index=4;group_index>=0;group_index=group_index-1)begin
            if(group_index<current_group &&
               next_down[group_index]>=(current_group-group_index>=2 ? 2 : 5))begin
                qualified=1'b1;
                qualified_group=group_index;
            end
        end
    end

    always @(posedge clk)begin
        if(!rst_n)begin
            auto_previous<=1'b0;
            initialize_pending<=1'b0;
            target_pending<=1'b0;
            target_mode<=4'd0;
            applied_mode<=4'd0;
            protect_active<=1'b0;
            protect_count<=4'd0;
            recovery_pending<=1'b0;
            watchdog<=16'd0;
            timeout<=1'b0;
            timeout_pulse<=1'b0;
            seq_valid<=1'b0;
            last_seq<=6'd0;
            packet_accept<=1'b0;
            vote_accept<=1'b0;
            reject_reason<=REJ_START;
            decision_pulse<=1'b0;
            adopt_pulse<=1'b0;
            candidate_count<=4'd0;
            for(sequential_index=0;sequential_index<5;sequential_index=sequential_index+1)begin
                up_count[sequential_index]<=3'd0;
                down_count[sequential_index]<=3'd0;
            end
            for(sequential_index=0;sequential_index<8;sequential_index=sequential_index+1)
                history[sequential_index]<=4'd15;
        end
        else begin
            auto_previous<=auto_enable;
            packet_accept<=1'b0;
            vote_accept<=1'b0;
            decision_pulse<=1'b0;
            adopt_pulse<=1'b0;
            timeout_pulse<=1'b0;

            // All fresh legal packets refresh the watchdog, also in manual,
            // protection or pending-adoption state. CRC validation is upstream.
            if(!link_started)begin
                watchdog<=16'd0;
                timeout<=1'b0;
                seq_valid<=1'b0;
            end
            else if(fresh_packet)begin
                watchdog<=16'd0;
                timeout<=1'b0;
                seq_valid<=1'b1;
                last_seq<=feedback_seq;
                packet_accept<=1'b1;
            end
            else if(!timeout)begin
                if(watchdog_event)begin
                    timeout<=1'b1;
                    timeout_pulse<=1'b1;
                    seq_valid<=1'b0;
                end
                else watchdog<=watchdog+1'b1;
            end
            if(packet_v)begin
                if(!legal_packet) reject_reason<=REJ_MODE;
                else if(!fresh_packet) reject_reason<=REJ_DUP;
                else if(!auto_enable) reject_reason<=REJ_MANUAL;
                else if(!link_started || automatic_entry || initialize_pending) reject_reason<=REJ_START;
                else if(feedback_current!=applied_mode) reject_reason<=REJ_CURRENT;
                else if(protect_active) reject_reason<=REJ_PROTECT;
                else if(target_pending || recovery_pending) reject_reason<=REJ_PENDING;
                else reject_reason<=REJ_NONE;
            end

            if(!auto_enable)begin
                // Manual controls feed the source directly. All automatic
                // requests and their residence state are discarded on exit.
                initialize_pending<=1'b0;
                target_pending<=1'b0;
                recovery_pending<=1'b0;
                protect_active<=1'b0;
                protect_count<=4'd0;
                candidate_count<=4'd0;
                if(frame_commit) applied_mode<=requested_mode;
                for(sequential_index=0;sequential_index<5;sequential_index=sequential_index+1)begin
                    up_count[sequential_index]<=3'd0;
                    down_count[sequential_index]<=3'd0;
                end
                for(sequential_index=0;sequential_index<8;sequential_index=sequential_index+1)
                    history[sequential_index]<=4'd15;
            end
            else if(automatic_entry)begin
                initialize_pending<=!frame_commit;
                target_pending<=1'b0;
                recovery_pending<=1'b0;
                target_mode<=4'd0;
                protect_active<=frame_commit;
                protect_count<=4'd0;
                candidate_count<=4'd0;
                seq_valid<=1'b0;
                watchdog<=16'd0;
                timeout<=1'b0;
                if(frame_commit)begin applied_mode<=4'd0; adopt_pulse<=1'b1; end
                for(sequential_index=0;sequential_index<5;sequential_index=sequential_index+1)begin
                    up_count[sequential_index]<=3'd0;
                    down_count[sequential_index]<=3'd0;
                end
                for(sequential_index=0;sequential_index<8;sequential_index=sequential_index+1)
                    history[sequential_index]<=4'd15;
            end
            else if(initialize_pending)begin
                if(frame_commit)begin
                    initialize_pending<=1'b0;
                    applied_mode<=4'd0;
                    protect_active<=1'b1;
                    protect_count<=4'd0;
                    adopt_pulse<=1'b1;
                end
            end
            else begin
                if(protect_active && tx_frame_done && physical_mode==applied_mode)begin
                    protect_count<=protect_count+1'b1;
                    if(protection_end) protect_active<=1'b0;
                end
                if(frame_commit && recovery_ready)begin
                    applied_mode<=4'd0;
                    recovery_pending<=1'b0;
                    target_pending<=1'b0;
                    target_mode<=4'd0;
                    adopt_pulse<=1'b1;
                    if(applied_mode!=0)begin
                        protect_active<=1'b1;
                        protect_count<=4'd0;
                    end
                end
                else if(frame_commit && target_pending && !protect_active)begin
                    applied_mode<=target_mode;
                    target_pending<=1'b0;
                    protect_active<=1'b1;
                    protect_count<=4'd0;
                    adopt_pulse<=1'b1;
                    candidate_count<=4'd0;
                    for(sequential_index=0;sequential_index<5;sequential_index=sequential_index+1)begin
                        up_count[sequential_index]<=3'd0;
                        down_count[sequential_index]<=3'd0;
                    end
                    for(sequential_index=0;sequential_index<8;sequential_index=sequential_index+1)
                        history[sequential_index]<=4'd15;
                end
                if(fresh_packet && may_vote)begin
                    vote_accept<=1'b1;
                    for(sequential_index=0;sequential_index<5;sequential_index=sequential_index+1)begin
                        up_count[sequential_index]<=next_up[sequential_index];
                        down_count[sequential_index]<=next_down[sequential_index];
                    end
                    history[0]<=feedback_target;
                    for(sequential_index=1;sequential_index<8;sequential_index=sequential_index+1)
                        history[sequential_index]<=history[sequential_index-1];
                    if(candidate_count<8) candidate_count<=candidate_count+1'b1;
                    if(qualified && chosen_mode!=applied_mode)begin
                        target_mode<=chosen_mode;
                        target_pending<=1'b1;
                        decision_pulse<=1'b1;
                    end
                end
                // Highest policy priority: one recovery request per outage.
                // An already confirmed normal request cannot defeat recovery;
                // a later good report cannot withdraw this recovery request.
                if(watchdog_event)begin
                    target_pending<=1'b0;
                    target_mode<=4'd0;
                    candidate_count<=4'd0;
                    if((frame_commit ? requested_mode : applied_mode)!=0)
                        recovery_pending<=1'b1;
                    else recovery_pending<=1'b0;
                    for(sequential_index=0;sequential_index<5;sequential_index=sequential_index+1)begin
                        up_count[sequential_index]<=3'd0;
                        down_count[sequential_index]<=3'd0;
                    end
                    for(sequential_index=0;sequential_index<8;sequential_index=sequential_index+1)
                        history[sequential_index]<=4'd15;
                end
            end
        end
    end
endmodule
`default_nettype wire
