export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      activity_levels: {
        Row: {
          active: boolean
          factor: number
          key: string
          label: string
          position: number
        }
        Insert: {
          active?: boolean
          factor: number
          key: string
          label: string
          position?: number
        }
        Update: {
          active?: boolean
          factor?: number
          key?: string
          label?: string
          position?: number
        }
        Relationships: []
      }
      afcd_master: {
        Row: {
          calcium_mg: number | null
          carb_avail: number | null
          classification: string | null
          energy_kcal: number | null
          fat: number | null
          fibre: number | null
          folate_ug: number | null
          food_name: string
          iron_mg: number | null
          magnesium_mg: number | null
          potassium_mg: number | null
          protein: number | null
          public_food_key: string
          satfat: number | null
          sodium_mg: number | null
          specific_gravity: number | null
          sugars: number | null
          vitamin_b12_ug: number | null
          zinc_mg: number | null
        }
        Insert: {
          calcium_mg?: number | null
          carb_avail?: number | null
          classification?: string | null
          energy_kcal?: number | null
          fat?: number | null
          fibre?: number | null
          folate_ug?: number | null
          food_name: string
          iron_mg?: number | null
          magnesium_mg?: number | null
          potassium_mg?: number | null
          protein?: number | null
          public_food_key: string
          satfat?: number | null
          sodium_mg?: number | null
          specific_gravity?: number | null
          sugars?: number | null
          vitamin_b12_ug?: number | null
          zinc_mg?: number | null
        }
        Update: {
          calcium_mg?: number | null
          carb_avail?: number | null
          classification?: string | null
          energy_kcal?: number | null
          fat?: number | null
          fibre?: number | null
          folate_ug?: number | null
          food_name?: string
          iron_mg?: number | null
          magnesium_mg?: number | null
          potassium_mg?: number | null
          protein?: number | null
          public_food_key?: string
          satfat?: number | null
          sodium_mg?: number | null
          specific_gravity?: number | null
          sugars?: number | null
          vitamin_b12_ug?: number | null
          zinc_mg?: number | null
        }
        Relationships: []
      }
      app_settings: {
        Row: {
          description: string | null
          key: string
          value: string
        }
        Insert: {
          description?: string | null
          key: string
          value: string
        }
        Update: {
          description?: string | null
          key?: string
          value?: string
        }
        Relationships: []
      }
      change_log: {
        Row: {
          action: string
          auto_unverified: boolean
          changed_at: string
          changed_by: string | null
          changes: Json
          entity: string
          food_id: string
          food_name: string | null
          id: number
          reviewed_at: string | null
          reviewed_by: string | null
          summary: string
        }
        Insert: {
          action: string
          auto_unverified?: boolean
          changed_at?: string
          changed_by?: string | null
          changes?: Json
          entity: string
          food_id: string
          food_name?: string | null
          id?: never
          reviewed_at?: string | null
          reviewed_by?: string | null
          summary: string
        }
        Update: {
          action?: string
          auto_unverified?: boolean
          changed_at?: string
          changed_by?: string | null
          changes?: Json
          entity?: string
          food_id?: string
          food_name?: string | null
          id?: never
          reviewed_at?: string | null
          reviewed_by?: string | null
          summary?: string
        }
        Relationships: [
          {
            foreignKeyName: "change_log_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_log_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_areas: {
        Row: {
          blurb: string
          icon: string | null
          key: string
          position: number
          status: string
          title: string
        }
        Insert: {
          blurb: string
          icon?: string | null
          key: string
          position?: number
          status?: string
          title: string
        }
        Update: {
          blurb?: string
          icon?: string | null
          key?: string
          position?: number
          status?: string
          title?: string
        }
        Relationships: []
      }
      client_checkins: {
        Row: {
          answers: Json
          bowels_bristol: number | null
          bowels_notes: string | null
          changes_wanted: string | null
          checkin_on: string
          client_id: string
          created_at: string
          dislikes: string | null
          energy: number | null
          entered_by: string | null
          feeling: number | null
          hunger: number | null
          id: string
          likes: string | null
          notes: string | null
          sleep: number | null
          source: string
          training: string | null
          updated_at: string
        }
        Insert: {
          answers?: Json
          bowels_bristol?: number | null
          bowels_notes?: string | null
          changes_wanted?: string | null
          checkin_on: string
          client_id: string
          created_at?: string
          dislikes?: string | null
          energy?: number | null
          entered_by?: string | null
          feeling?: number | null
          hunger?: number | null
          id?: string
          likes?: string | null
          notes?: string | null
          sleep?: number | null
          source?: string
          training?: string | null
          updated_at?: string
        }
        Update: {
          answers?: Json
          bowels_bristol?: number | null
          bowels_notes?: string | null
          changes_wanted?: string | null
          checkin_on?: string
          client_id?: string
          created_at?: string
          dislikes?: string | null
          energy?: number | null
          entered_by?: string | null
          feeling?: number | null
          hunger?: number | null
          id?: string
          likes?: string | null
          notes?: string | null
          sleep?: number | null
          source?: string
          training?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_checkins_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_checkins_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_checkins_entered_by_fkey"
            columns: ["entered_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_clinical_records: {
        Row: {
          client_id: string
          client_note: string | null
          created_at: string
          file_path: string | null
          id: string
          kind: string
          measurements: Json | null
          recorded_on: string
          reviewed_at: string | null
          reviewed_by: string | null
          reviewed_by_name: string | null
          source: string
          summary: string | null
          uploaded_by: string | null
        }
        Insert: {
          client_id: string
          client_note?: string | null
          created_at?: string
          file_path?: string | null
          id?: string
          kind: string
          measurements?: Json | null
          recorded_on: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewed_by_name?: string | null
          source?: string
          summary?: string | null
          uploaded_by?: string | null
        }
        Update: {
          client_id?: string
          client_note?: string | null
          created_at?: string
          file_path?: string | null
          id?: string
          kind?: string
          measurements?: Json | null
          recorded_on?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewed_by_name?: string | null
          source?: string
          summary?: string | null
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_clinical_records_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_clinical_records_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_clinical_records_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_clinical_records_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_food_rules: {
        Row: {
          added_by: string | null
          client_id: string
          created_at: string
          food_id: string
          note: string | null
          primary_only: boolean
          rule: string
        }
        Insert: {
          added_by?: string | null
          client_id: string
          created_at?: string
          food_id: string
          note?: string | null
          primary_only?: boolean
          rule: string
        }
        Update: {
          added_by?: string | null
          client_id?: string
          created_at?: string
          food_id?: string
          note?: string | null
          primary_only?: boolean
          rule?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_food_rules_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_food_rules_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_food_rules_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_food_rules_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "client_food_rules_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
        ]
      }
      client_goals: {
        Row: {
          client_id: string
          created_at: string
          detail: string | null
          ended_on: string | null
          goal_type: string
          id: string
          is_primary: boolean
          set_by: string | null
          target_date: string | null
        }
        Insert: {
          client_id: string
          created_at?: string
          detail?: string | null
          ended_on?: string | null
          goal_type: string
          id?: string
          is_primary?: boolean
          set_by?: string | null
          target_date?: string | null
        }
        Update: {
          client_id?: string
          created_at?: string
          detail?: string | null
          ended_on?: string | null
          goal_type?: string
          id?: string
          is_primary?: boolean
          set_by?: string | null
          target_date?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_goals_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_goals_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_goals_goal_type_fkey"
            columns: ["goal_type"]
            isOneToOne: false
            referencedRelation: "goal_types"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "client_goals_set_by_fkey"
            columns: ["set_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_intake: {
        Row: {
          answers: Json
          client_id: string
          question_keys: string[] | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          submitted_at: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          answers?: Json
          client_id: string
          question_keys?: string[] | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          submitted_at?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          answers?: Json
          client_id?: string
          question_keys?: string[] | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          submitted_at?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_intake_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_intake_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_intake_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_intake_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_intake_log: {
        Row: {
          action: string
          changed_at: string
          changed_by: string | null
          client_id: string
          field: string
          id: number
          new_value: string | null
          old_value: string | null
        }
        Insert: {
          action: string
          changed_at?: string
          changed_by?: string | null
          client_id: string
          field: string
          id?: never
          new_value?: string | null
          old_value?: string | null
        }
        Update: {
          action?: string
          changed_at?: string
          changed_by?: string | null
          client_id?: string
          field?: string
          id?: never
          new_value?: string | null
          old_value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_intake_log_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_intake_log_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_intake_log_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      client_meal_slots: {
        Row: {
          client_id: string
          energy_share: number | null
          free_choice: boolean
          id: string
          name: string
          position: number
          slot_kind: string
          time_of_day: string | null
        }
        Insert: {
          client_id: string
          energy_share?: number | null
          free_choice?: boolean
          id?: string
          name: string
          position: number
          slot_kind: string
          time_of_day?: string | null
        }
        Update: {
          client_id?: string
          energy_share?: number | null
          free_choice?: boolean
          id?: string
          name?: string
          position?: number
          slot_kind?: string
          time_of_day?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_meal_slots_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_meal_slots_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      client_protein_preferences: {
        Row: {
          client_id: string
          preference: string
          protein_family: string
        }
        Insert: {
          client_id: string
          preference: string
          protein_family: string
        }
        Update: {
          client_id?: string
          preference?: string
          protein_family?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_protein_preferences_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_protein_preferences_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_protein_preferences_protein_family_fkey"
            columns: ["protein_family"]
            isOneToOne: false
            referencedRelation: "protein_families"
            referencedColumns: ["key"]
          },
        ]
      }
      client_protein_spread: {
        Row: {
          client_id: string
          count_per_cycle: number
          protein_family: string
        }
        Insert: {
          client_id: string
          count_per_cycle: number
          protein_family: string
        }
        Update: {
          client_id?: string
          count_per_cycle?: number
          protein_family?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_protein_spread_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_protein_spread_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_protein_spread_protein_family_fkey"
            columns: ["protein_family"]
            isOneToOne: false
            referencedRelation: "protein_families"
            referencedColumns: ["key"]
          },
        ]
      }
      client_requirements: {
        Row: {
          added_by: string | null
          client_id: string
          created_at: string
          note: string | null
          tag_id: string
        }
        Insert: {
          added_by?: string | null
          client_id: string
          created_at?: string
          note?: string | null
          tag_id: string
        }
        Update: {
          added_by?: string | null
          client_id?: string
          created_at?: string
          note?: string | null
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_requirements_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_requirements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_requirements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_requirements_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      client_staff_access: {
        Row: {
          can_view_checkins: boolean
          client_id: string
          granted_at: string
          granted_by: string | null
          profile_id: string
        }
        Insert: {
          can_view_checkins?: boolean
          client_id: string
          granted_at?: string
          granted_by?: string | null
          profile_id: string
        }
        Update: {
          can_view_checkins?: boolean
          client_id?: string
          granted_at?: string
          granted_by?: string | null
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_staff_access_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_staff_access_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_staff_access_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_staff_access_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_structure: {
        Row: {
          batch_cooking: boolean
          client_id: string
          cycle_length_days: number | null
          day_type_pattern: string[]
          repeat_max_per_cycle: number | null
          repeat_min_gap_days: number | null
          updated_at: string
        }
        Insert: {
          batch_cooking?: boolean
          client_id: string
          cycle_length_days?: number | null
          day_type_pattern?: string[]
          repeat_max_per_cycle?: number | null
          repeat_min_gap_days?: number | null
          updated_at?: string
        }
        Update: {
          batch_cooking?: boolean
          client_id?: string
          cycle_length_days?: number | null
          day_type_pattern?: string[]
          repeat_max_per_cycle?: number | null
          repeat_min_gap_days?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_structure_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_structure_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      client_supplements: {
        Row: {
          added_by: string | null
          client_id: string
          created_at: string
          dose: string | null
          ended_on: string | null
          id: string
          name: string
          notes: string | null
          position: number
          started_on: string | null
          timing: string | null
        }
        Insert: {
          added_by?: string | null
          client_id: string
          created_at?: string
          dose?: string | null
          ended_on?: string | null
          id?: string
          name: string
          notes?: string | null
          position?: number
          started_on?: string | null
          timing?: string | null
        }
        Update: {
          added_by?: string | null
          client_id?: string
          created_at?: string
          dose?: string | null
          ended_on?: string | null
          id?: string
          name?: string
          notes?: string | null
          position?: number
          started_on?: string | null
          timing?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_supplements_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_supplements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_supplements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      client_targets: {
        Row: {
          calc_inputs: Json | null
          carb_g: number | null
          client_id: string
          day_type: string
          fat_g: number | null
          fibre_g: number | null
          id: string
          kcal: number | null
          note: string | null
          protein_g: number | null
          set_by: string | null
          set_on: string
          source: string
        }
        Insert: {
          calc_inputs?: Json | null
          carb_g?: number | null
          client_id: string
          day_type: string
          fat_g?: number | null
          fibre_g?: number | null
          id?: string
          kcal?: number | null
          note?: string | null
          protein_g?: number | null
          set_by?: string | null
          set_on?: string
          source: string
        }
        Update: {
          calc_inputs?: Json | null
          carb_g?: number | null
          client_id?: string
          day_type?: string
          fat_g?: number | null
          fibre_g?: number | null
          id?: string
          kcal?: number | null
          note?: string | null
          protein_g?: number | null
          set_by?: string | null
          set_on?: string
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_targets_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_targets_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_targets_set_by_fkey"
            columns: ["set_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_weights: {
        Row: {
          checkin_id: string | null
          client_id: string
          created_at: string
          entered_by: string | null
          id: string
          note: string | null
          recorded_on: string
          source: string
          weight_kg: number
        }
        Insert: {
          checkin_id?: string | null
          client_id: string
          created_at?: string
          entered_by?: string | null
          id?: string
          note?: string | null
          recorded_on: string
          source?: string
          weight_kg: number
        }
        Update: {
          checkin_id?: string | null
          client_id?: string
          created_at?: string
          entered_by?: string | null
          id?: string
          note?: string | null
          recorded_on?: string
          source?: string
          weight_kg?: number
        }
        Relationships: [
          {
            foreignKeyName: "client_weights_checkin_id_fkey"
            columns: ["checkin_id"]
            isOneToOne: false
            referencedRelation: "client_checkins"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_weights_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_weights_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_weights_entered_by_fkey"
            columns: ["entered_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          activity_level: string | null
          assigned_dietitian: string | null
          client_shows_numbers: boolean
          created_at: string
          date_of_birth: string | null
          email: string | null
          equation_sex: string | null
          full_name: string
          height_cm: number | null
          id: string
          notes: string | null
          numbers_allowed: boolean
          phone: string | null
          protein_g_per_kg: number | null
          sex: string
          source: string
          status: string
          user_id: string | null
        }
        Insert: {
          activity_level?: string | null
          assigned_dietitian?: string | null
          client_shows_numbers?: boolean
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          equation_sex?: string | null
          full_name: string
          height_cm?: number | null
          id?: string
          notes?: string | null
          numbers_allowed?: boolean
          phone?: string | null
          protein_g_per_kg?: number | null
          sex?: string
          source?: string
          status?: string
          user_id?: string | null
        }
        Update: {
          activity_level?: string | null
          assigned_dietitian?: string | null
          client_shows_numbers?: boolean
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          equation_sex?: string | null
          full_name?: string
          height_cm?: number | null
          id?: string
          notes?: string | null
          numbers_allowed?: boolean
          phone?: string | null
          protein_g_per_kg?: number | null
          sex?: string
          source?: string
          status?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clients_activity_level_fkey"
            columns: ["activity_level"]
            isOneToOne: false
            referencedRelation: "activity_levels"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "clients_assigned_dietitian_fkey"
            columns: ["assigned_dietitian"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clients_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      credential_types: {
        Row: {
          active: boolean
          has_issuer: boolean
          has_number: boolean
          has_state: boolean
          help: string | null
          key: string
          label: string
          position: number
          renew_months: number | null
          required_for: string[]
          roles: string[]
        }
        Insert: {
          active?: boolean
          has_issuer?: boolean
          has_number?: boolean
          has_state?: boolean
          help?: string | null
          key: string
          label: string
          position?: number
          renew_months?: number | null
          required_for?: string[]
          roles?: string[]
        }
        Update: {
          active?: boolean
          has_issuer?: boolean
          has_number?: boolean
          has_state?: boolean
          help?: string | null
          key?: string
          label?: string
          position?: number
          renew_months?: number | null
          required_for?: string[]
          roles?: string[]
        }
        Relationships: []
      }
      food_tags: {
        Row: {
          food_id: string
          tag_id: string
        }
        Insert: {
          food_id: string
          tag_id: string
        }
        Update: {
          food_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_tags_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "food_tags_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "food_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      food_unit_exclusions: {
        Row: {
          food_id: string
          unit: string
        }
        Insert: {
          food_id: string
          unit: string
        }
        Update: {
          food_id?: string
          unit?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_unit_exclusions_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "food_unit_exclusions_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
        ]
      }
      foods: {
        Row: {
          afcd_key: string | null
          aisle: string | null
          calcium_100g: number | null
          carb_avail_100g: number | null
          default_size: string | null
          density_g_ml: number | null
          display_name: string
          energy_kcal_100g: number | null
          fat_100g: number | null
          fibre_100g: number | null
          folate_100g: number | null
          food_id: string
          iron_100g: number | null
          magnesium_100g: number | null
          match_note: string | null
          potassium_100g: number | null
          protein_100g: number | null
          protein_family: string | null
          purchase_unit: string | null
          role: string | null
          satfat_100g: number | null
          sodium_100g: number | null
          source: Database["public"]["Enums"]["food_source"]
          sugars_100g: number | null
          verified: boolean
          vitamin_b12_100g: number | null
          zinc_100g: number | null
        }
        Insert: {
          afcd_key?: string | null
          aisle?: string | null
          calcium_100g?: number | null
          carb_avail_100g?: number | null
          default_size?: string | null
          density_g_ml?: number | null
          display_name: string
          energy_kcal_100g?: number | null
          fat_100g?: number | null
          fibre_100g?: number | null
          folate_100g?: number | null
          food_id: string
          iron_100g?: number | null
          magnesium_100g?: number | null
          match_note?: string | null
          potassium_100g?: number | null
          protein_100g?: number | null
          protein_family?: string | null
          purchase_unit?: string | null
          role?: string | null
          satfat_100g?: number | null
          sodium_100g?: number | null
          source: Database["public"]["Enums"]["food_source"]
          sugars_100g?: number | null
          verified?: boolean
          vitamin_b12_100g?: number | null
          zinc_100g?: number | null
        }
        Update: {
          afcd_key?: string | null
          aisle?: string | null
          calcium_100g?: number | null
          carb_avail_100g?: number | null
          default_size?: string | null
          density_g_ml?: number | null
          display_name?: string
          energy_kcal_100g?: number | null
          fat_100g?: number | null
          fibre_100g?: number | null
          folate_100g?: number | null
          food_id?: string
          iron_100g?: number | null
          magnesium_100g?: number | null
          match_note?: string | null
          potassium_100g?: number | null
          protein_100g?: number | null
          protein_family?: string | null
          purchase_unit?: string | null
          role?: string | null
          satfat_100g?: number | null
          sodium_100g?: number | null
          source?: Database["public"]["Enums"]["food_source"]
          sugars_100g?: number | null
          verified?: boolean
          vitamin_b12_100g?: number | null
          zinc_100g?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "foods_protein_family_fkey"
            columns: ["protein_family"]
            isOneToOne: false
            referencedRelation: "protein_families"
            referencedColumns: ["key"]
          },
        ]
      }
      goal_types: {
        Row: {
          active: boolean
          category: string
          key: string
          label: string
          position: number
        }
        Insert: {
          active?: boolean
          category: string
          key: string
          label: string
          position?: number
        }
        Update: {
          active?: boolean
          category?: string
          key?: string
          label?: string
          position?: number
        }
        Relationships: []
      }
      ingredient_lines: {
        Row: {
          food_id: string
          id: string
          position: number
          prep_note: string | null
          quantity: number
          recipe_id: string
          section: string | null
          unit: string
        }
        Insert: {
          food_id: string
          id?: string
          position: number
          prep_note?: string | null
          quantity: number
          recipe_id: string
          section?: string | null
          unit: string
        }
        Update: {
          food_id?: string
          id?: string
          position?: number
          prep_note?: string | null
          quantity?: number
          recipe_id?: string
          section?: string | null
          unit?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      intake_questions: {
        Row: {
          active: boolean
          clinical: boolean
          help: string | null
          key: string
          kind: string
          label: string
          locked: boolean
          options: Json | null
          position: number
          required: boolean
          section: string
        }
        Insert: {
          active?: boolean
          clinical?: boolean
          help?: string | null
          key: string
          kind: string
          label: string
          locked?: boolean
          options?: Json | null
          position?: number
          required?: boolean
          section: string
        }
        Update: {
          active?: boolean
          clinical?: boolean
          help?: string | null
          key?: string
          kind?: string
          label?: string
          locked?: boolean
          options?: Json | null
          position?: number
          required?: boolean
          section?: string
        }
        Relationships: [
          {
            foreignKeyName: "intake_questions_section_fkey"
            columns: ["section"]
            isOneToOne: false
            referencedRelation: "intake_sections"
            referencedColumns: ["key"]
          },
        ]
      }
      intake_sections: {
        Row: {
          active: boolean
          builtins: string[]
          key: string
          position: number
          title: string
        }
        Insert: {
          active?: boolean
          builtins?: string[]
          key: string
          position?: number
          title: string
        }
        Update: {
          active?: boolean
          builtins?: string[]
          key?: string
          position?: number
          title?: string
        }
        Relationships: []
      }
      invitations: {
        Row: {
          accepted_at: string | null
          client_id: string | null
          created_at: string
          email: string
          expires_at: string | null
          id: string
          invited_by: string | null
          role: string
          token: string
        }
        Insert: {
          accepted_at?: string | null
          client_id?: string | null
          created_at?: string
          email: string
          expires_at?: string | null
          id?: string
          invited_by?: string | null
          role?: string
          token?: string
        }
        Update: {
          accepted_at?: string | null
          client_id?: string | null
          created_at?: string
          email?: string
          expires_at?: string | null
          id?: string
          invited_by?: string | null
          role?: string
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitations_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "invitations_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_plan_days: {
        Row: {
          day: number
          day_type: string
          meal_plan_id: string
        }
        Insert: {
          day: number
          day_type: string
          meal_plan_id: string
        }
        Update: {
          day?: number
          day_type?: string
          meal_plan_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_plan_days_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_plan_item_deltas: {
        Row: {
          base_food_id: string | null
          base_quantity: number | null
          base_section: string | null
          base_unit: string | null
          created_at: string
          id: string
          item_id: string
          kind: string
          line_ref: string | null
          new_food_id: string | null
          new_quantity: number | null
          new_unit: string | null
          position: number
          source: string
        }
        Insert: {
          base_food_id?: string | null
          base_quantity?: number | null
          base_section?: string | null
          base_unit?: string | null
          created_at?: string
          id?: string
          item_id: string
          kind: string
          line_ref?: string | null
          new_food_id?: string | null
          new_quantity?: number | null
          new_unit?: string | null
          position?: number
          source?: string
        }
        Update: {
          base_food_id?: string | null
          base_quantity?: number | null
          base_section?: string | null
          base_unit?: string | null
          created_at?: string
          id?: string
          item_id?: string
          kind?: string
          line_ref?: string | null
          new_food_id?: string | null
          new_quantity?: number | null
          new_unit?: string | null
          position?: number
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_plan_item_deltas_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "meal_plan_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plan_item_deltas_new_food_id_fkey"
            columns: ["new_food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "meal_plan_item_deltas_new_food_id_fkey"
            columns: ["new_food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
        ]
      }
      meal_plan_items: {
        Row: {
          batch_group: string | null
          batch_role: string | null
          boosts_item_id: string | null
          day: number | null
          food_id: string | null
          id: string
          meal_plan_id: string
          meal_slot: string | null
          option_of: string | null
          position: number
          profile_id: string | null
          quantity: number | null
          recipe_id: string | null
          servings_override: number | null
          unit: string | null
        }
        Insert: {
          batch_group?: string | null
          batch_role?: string | null
          boosts_item_id?: string | null
          day?: number | null
          food_id?: string | null
          id?: string
          meal_plan_id: string
          meal_slot?: string | null
          option_of?: string | null
          position: number
          profile_id?: string | null
          quantity?: number | null
          recipe_id?: string | null
          servings_override?: number | null
          unit?: string | null
        }
        Update: {
          batch_group?: string | null
          batch_role?: string | null
          boosts_item_id?: string | null
          day?: number | null
          food_id?: string | null
          id?: string
          meal_plan_id?: string
          meal_slot?: string | null
          option_of?: string | null
          position?: number
          profile_id?: string | null
          quantity?: number | null
          recipe_id?: string | null
          servings_override?: number | null
          unit?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "meal_plan_items_boosts_item_id_fkey"
            columns: ["boosts_item_id"]
            isOneToOne: false
            referencedRelation: "meal_plan_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plan_items_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "meal_plan_items_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "meal_plan_items_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plan_items_option_of_fkey"
            columns: ["option_of"]
            isOneToOne: false
            referencedRelation: "meal_plan_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plan_items_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "recipe_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plan_items_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "meal_plan_items_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "meal_plan_items_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_plan_slot_states: {
        Row: {
          day: number
          locked: boolean
          meal_plan_id: string
          meal_slot: string
          reason: string | null
          state: string | null
        }
        Insert: {
          day: number
          locked?: boolean
          meal_plan_id: string
          meal_slot: string
          reason?: string | null
          state?: string | null
        }
        Update: {
          day?: number
          locked?: boolean
          meal_plan_id?: string
          meal_slot?: string
          reason?: string | null
          state?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "meal_plan_slot_states_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_plan_versions: {
        Row: {
          confirmed_at: string | null
          confirmed_by_name: string | null
          generation_id: string | null
          id: string
          meal_plan_id: string
          needs_review_recipes: string[]
          published_at: string
          published_by: string | null
          published_by_name: string
          release_on: string | null
          review_notes: string | null
          snapshot: Json
          version_no: number
        }
        Insert: {
          confirmed_at?: string | null
          confirmed_by_name?: string | null
          generation_id?: string | null
          id?: string
          meal_plan_id: string
          needs_review_recipes?: string[]
          published_at?: string
          published_by?: string | null
          published_by_name: string
          release_on?: string | null
          review_notes?: string | null
          snapshot: Json
          version_no: number
        }
        Update: {
          confirmed_at?: string | null
          confirmed_by_name?: string | null
          generation_id?: string | null
          id?: string
          meal_plan_id?: string
          needs_review_recipes?: string[]
          published_at?: string
          published_by?: string | null
          published_by_name?: string
          release_on?: string | null
          review_notes?: string | null
          snapshot?: Json
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "meal_plan_versions_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plan_versions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_plans: {
        Row: {
          client_id: string | null
          confirmed_at: string | null
          confirmed_by: string | null
          confirmed_by_name: string | null
          created_at: string
          days: number | null
          generation_id: string | null
          id: string
          notes: string | null
          report: Json | null
          report_at: string | null
          review_notes: string | null
          start_date: string | null
          status: string
          title: string
        }
        Insert: {
          client_id?: string | null
          confirmed_at?: string | null
          confirmed_by?: string | null
          confirmed_by_name?: string | null
          created_at?: string
          days?: number | null
          generation_id?: string | null
          id?: string
          notes?: string | null
          report?: Json | null
          report_at?: string | null
          review_notes?: string | null
          start_date?: string | null
          status?: string
          title: string
        }
        Update: {
          client_id?: string | null
          confirmed_at?: string | null
          confirmed_by?: string | null
          confirmed_by_name?: string | null
          created_at?: string
          days?: number | null
          generation_id?: string | null
          id?: string
          notes?: string | null
          report?: Json | null
          report_at?: string | null
          review_notes?: string | null
          start_date?: string | null
          status?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_plans_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "meal_plans_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plans_confirmed_by_fkey"
            columns: ["confirmed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plans_generation_id_fkey"
            columns: ["generation_id"]
            isOneToOne: false
            referencedRelation: "plan_generations"
            referencedColumns: ["id"]
          },
        ]
      }
      method_steps: {
        Row: {
          id: string
          position: number
          recipe_id: string
          text: string
        }
        Insert: {
          id?: string
          position: number
          recipe_id: string
          text: string
        }
        Update: {
          id?: string
          position?: number
          recipe_id?: string
          text?: string
        }
        Relationships: [
          {
            foreignKeyName: "method_steps_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "method_steps_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "method_steps_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      plan_edits: {
        Row: {
          actor: string | null
          actor_name: string | null
          created_at: string
          diff: Json
          id: number
          meal_plan_id: string
          operation: string
        }
        Insert: {
          actor?: string | null
          actor_name?: string | null
          created_at?: string
          diff?: Json
          id?: never
          meal_plan_id: string
          operation: string
        }
        Update: {
          actor?: string | null
          actor_name?: string | null
          created_at?: string
          diff?: Json
          id?: never
          meal_plan_id?: string
          operation?: string
        }
        Relationships: [
          {
            foreignKeyName: "plan_edits_actor_fkey"
            columns: ["actor"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_edits_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      plan_generations: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          meal_plan_id: string
          planner_version: string
          pool_hash: string
          report: Json
          seed: number
          settings: Json
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          meal_plan_id: string
          planner_version: string
          pool_hash: string
          report: Json
          seed: number
          settings: Json
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          meal_plan_id?: string
          planner_version?: string
          pool_hash?: string
          report?: Json
          seed?: number
          settings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "plan_generations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_generations_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_generations_pool_hash_fkey"
            columns: ["pool_hash"]
            isOneToOne: false
            referencedRelation: "plan_pool_snapshots"
            referencedColumns: ["hash"]
          },
        ]
      }
      plan_pool_snapshots: {
        Row: {
          content: Json
          created_at: string
          hash: string
          recipe_count: number
        }
        Insert: {
          content: Json
          created_at?: string
          hash: string
          recipe_count: number
        }
        Update: {
          content?: Json
          created_at?: string
          hash?: string
          recipe_count?: number
        }
        Relationships: []
      }
      profiles: {
        Row: {
          bio: string | null
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          job_title: string | null
          organisation: string | null
          phone: string | null
          photo_path: string | null
          placement_end: string | null
          placement_start: string | null
          preferred_name: string | null
          pronouns: string | null
          role: string
          supervisor_id: string | null
          university: string | null
        }
        Insert: {
          bio?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id: string
          job_title?: string | null
          organisation?: string | null
          phone?: string | null
          photo_path?: string | null
          placement_end?: string | null
          placement_start?: string | null
          preferred_name?: string | null
          pronouns?: string | null
          role?: string
          supervisor_id?: string | null
          university?: string | null
        }
        Update: {
          bio?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          job_title?: string | null
          organisation?: string | null
          phone?: string | null
          photo_path?: string | null
          placement_end?: string | null
          placement_start?: string | null
          preferred_name?: string | null
          pronouns?: string | null
          role?: string
          supervisor_id?: string | null
          university?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profiles_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      protein_families: {
        Row: {
          active: boolean
          key: string
          label: string
          position: number
        }
        Insert: {
          active?: boolean
          key: string
          label: string
          position?: number
        }
        Update: {
          active?: boolean
          key?: string
          label?: string
          position?: number
        }
        Relationships: []
      }
      recipe_profile_deltas: {
        Row: {
          base_food_id: string | null
          base_quantity: number | null
          base_section: string | null
          base_unit: string | null
          id: string
          kind: string
          line_ref: string | null
          new_food_id: string | null
          new_quantity: number | null
          new_unit: string | null
          position: number
          profile_id: string
        }
        Insert: {
          base_food_id?: string | null
          base_quantity?: number | null
          base_section?: string | null
          base_unit?: string | null
          id?: string
          kind: string
          line_ref?: string | null
          new_food_id?: string | null
          new_quantity?: number | null
          new_unit?: string | null
          position?: number
          profile_id: string
        }
        Update: {
          base_food_id?: string | null
          base_quantity?: number | null
          base_section?: string | null
          base_unit?: string | null
          id?: string
          kind?: string
          line_ref?: string | null
          new_food_id?: string | null
          new_quantity?: number | null
          new_unit?: string | null
          position?: number
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recipe_profile_deltas_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "recipe_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_profiles: {
        Row: {
          base_fingerprint: string | null
          created_at: string
          id: string
          name: string
          origin: string
          position: number
          recipe_id: string
          verified: boolean
          verified_fingerprint: string | null
        }
        Insert: {
          base_fingerprint?: string | null
          created_at?: string
          id?: string
          name: string
          origin?: string
          position?: number
          recipe_id: string
          verified?: boolean
          verified_fingerprint?: string | null
        }
        Update: {
          base_fingerprint?: string | null
          created_at?: string
          id?: string
          name?: string
          origin?: string
          position?: number
          recipe_id?: string
          verified?: boolean
          verified_fingerprint?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recipe_profiles_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_profiles_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_profiles_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_signoffs: {
        Row: {
          id: string
          recipe_id: string
          revoke_note: string | null
          revoked_at: string | null
          revoked_by: string | null
          signed_at: string
          signed_by: string | null
          signed_by_name: string
        }
        Insert: {
          id?: string
          recipe_id: string
          revoke_note?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          signed_at?: string
          signed_by?: string | null
          signed_by_name: string
        }
        Update: {
          id?: string
          recipe_id?: string
          revoke_note?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          signed_at?: string
          signed_by?: string | null
          signed_by_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "recipe_signoffs_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_signoffs_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_signoffs_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_signoffs_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_signoffs_signed_by_fkey"
            columns: ["signed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_tag_overrides: {
        Row: {
          action: Database["public"]["Enums"]["override_action"]
          recipe_id: string
          tag_id: string
        }
        Insert: {
          action: Database["public"]["Enums"]["override_action"]
          recipe_id: string
          tag_id: string
        }
        Update: {
          action?: Database["public"]["Enums"]["override_action"]
          recipe_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recipe_tag_overrides_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_tag_overrides_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_tag_overrides_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_tag_overrides_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_tags: {
        Row: {
          recipe_id: string
          source: string
          tag_id: string
        }
        Insert: {
          recipe_id: string
          source?: string
          tag_id: string
        }
        Update: {
          recipe_id?: string
          source?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recipe_tags_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_tags_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipe_tags_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      recipes: {
        Row: {
          data_issue: string | null
          id: string
          image_url_1: string | null
          image_url_2: string | null
          servings: number
          show_macros_export: boolean
          time_minutes: number | null
          title: string
          variant_of: string | null
        }
        Insert: {
          data_issue?: string | null
          id?: string
          image_url_1?: string | null
          image_url_2?: string | null
          servings: number
          show_macros_export?: boolean
          time_minutes?: number | null
          title: string
          variant_of?: string | null
        }
        Update: {
          data_issue?: string | null
          id?: string
          image_url_1?: string | null
          image_url_2?: string | null
          servings?: number
          show_macros_export?: boolean
          time_minutes?: number | null
          title?: string
          variant_of?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recipes_variant_of_fkey"
            columns: ["variant_of"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipes_variant_of_fkey"
            columns: ["variant_of"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "recipes_variant_of_fkey"
            columns: ["variant_of"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_views: {
        Row: {
          created_at: string
          id: string
          name: string
          screen: string
          state: Json
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          screen: string
          state: Json
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          screen?: string
          state?: Json
          user_id?: string
        }
        Relationships: []
      }
      staff_credentials: {
        Row: {
          checked_at: string | null
          checked_by: string | null
          created_at: string
          expires_on: string | null
          file_path: string | null
          id: string
          issued_on: string | null
          issuer: string | null
          note: string | null
          number: string | null
          profile_id: string
          state: string | null
          type: string
          updated_at: string
        }
        Insert: {
          checked_at?: string | null
          checked_by?: string | null
          created_at?: string
          expires_on?: string | null
          file_path?: string | null
          id?: string
          issued_on?: string | null
          issuer?: string | null
          note?: string | null
          number?: string | null
          profile_id: string
          state?: string | null
          type: string
          updated_at?: string
        }
        Update: {
          checked_at?: string | null
          checked_by?: string | null
          created_at?: string
          expires_on?: string | null
          file_path?: string | null
          id?: string
          issued_on?: string | null
          issuer?: string | null
          note?: string | null
          number?: string | null
          profile_id?: string
          state?: string | null
          type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_credentials_checked_by_fkey"
            columns: ["checked_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_credentials_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_credentials_type_fkey"
            columns: ["type"]
            isOneToOne: false
            referencedRelation: "credential_types"
            referencedColumns: ["key"]
          },
        ]
      }
      swap_suggestions: {
        Row: {
          applies_for_tag_id: string
          id: string
          notes: string | null
          position: number
          suggestion_food_id: string | null
          suggestion_name: string
          trigger_food_id: string | null
          trigger_tag_id: string | null
        }
        Insert: {
          applies_for_tag_id: string
          id?: string
          notes?: string | null
          position?: number
          suggestion_food_id?: string | null
          suggestion_name: string
          trigger_food_id?: string | null
          trigger_tag_id?: string | null
        }
        Update: {
          applies_for_tag_id?: string
          id?: string
          notes?: string | null
          position?: number
          suggestion_food_id?: string | null
          suggestion_name?: string
          trigger_food_id?: string | null
          trigger_tag_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "swap_suggestions_applies_for_tag_id_fkey"
            columns: ["applies_for_tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "swap_suggestions_suggestion_food_id_fkey"
            columns: ["suggestion_food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "swap_suggestions_suggestion_food_id_fkey"
            columns: ["suggestion_food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "swap_suggestions_trigger_food_id_fkey"
            columns: ["trigger_food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "swap_suggestions_trigger_food_id_fkey"
            columns: ["trigger_food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "swap_suggestions_trigger_tag_id_fkey"
            columns: ["trigger_tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      tag_blockers: {
        Row: {
          blocks_tag_id: string
          tag_id: string
        }
        Insert: {
          blocks_tag_id: string
          tag_id: string
        }
        Update: {
          blocks_tag_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tag_blockers_blocks_tag_id_fkey"
            columns: ["blocks_tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tag_blockers_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      tags: {
        Row: {
          category: string
          id: string
          kind: Database["public"]["Enums"]["tag_kind"] | null
          label: string
        }
        Insert: {
          category: string
          id?: string
          kind?: Database["public"]["Enums"]["tag_kind"] | null
          label: string
        }
        Update: {
          category?: string
          id?: string
          kind?: Database["public"]["Enums"]["tag_kind"] | null
          label?: string
        }
        Relationships: []
      }
      unit_conversions: {
        Row: {
          basis: string | null
          estimated: boolean
          food_id: string
          grams: number
          id: number
          unit: string
        }
        Insert: {
          basis?: string | null
          estimated?: boolean
          food_id: string
          grams: number
          id?: never
          unit: string
        }
        Update: {
          basis?: string | null
          estimated?: boolean
          food_id?: string
          grams?: number
          id?: never
          unit?: string
        }
        Relationships: [
          {
            foreignKeyName: "unit_conversions_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "unit_conversions_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
        ]
      }
    }
    Views: {
      changes_to_review: {
        Row: {
          action: string | null
          auto_unverified: boolean | null
          changed_at: string | null
          changed_by: string | null
          changed_by_name: string | null
          changes: Json | null
          entity: string | null
          food_id: string | null
          food_name: string | null
          food_verified_now: boolean | null
          id: number | null
          summary: string | null
        }
        Relationships: [
          {
            foreignKeyName: "change_log_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_blocked_tags: {
        Row: {
          because_label: string | null
          because_tag_id: string | null
          blocked_label: string | null
          blocked_tag_id: string | null
          client_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_requirements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_requirements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_requirements_tag_id_fkey"
            columns: ["because_tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      client_current_targets: {
        Row: {
          calc_inputs: Json | null
          carb_g: number | null
          client_id: string | null
          day_type: string | null
          fat_g: number | null
          fibre_g: number | null
          id: string | null
          kcal: number | null
          note: string | null
          protein_g: number | null
          set_by: string | null
          set_on: string | null
          source: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_targets_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_targets_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_targets_set_by_fkey"
            columns: ["set_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_overview: {
        Row: {
          assigned_dietitian: string | null
          assigned_dietitian_name: string | null
          client_id: string | null
          default_kcal: number | null
          full_name: string | null
          has_app_account: boolean | null
          intake_status: string | null
          intake_submitted_at: string | null
          latest_checkin_on: string | null
          latest_weight_kg: number | null
          latest_weight_on: string | null
          plan_count: number | null
          primary_goal: string | null
          primary_goal_label: string | null
          source: string | null
          status: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_goals_goal_type_fkey"
            columns: ["primary_goal"]
            isOneToOne: false
            referencedRelation: "goal_types"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "clients_assigned_dietitian_fkey"
            columns: ["assigned_dietitian"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      client_preferred_tags: {
        Row: {
          client_id: string | null
          label: string | null
          tag_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_requirements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "client_overview"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "client_requirements_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_requirements_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      conversion_gaps: {
        Row: {
          affected_recipes: number | null
          food_id: string | null
          unit: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
        ]
      }
      food_leverage: {
        Row: {
          blocked_recipes: number | null
          display_name: string | null
          food_id: string | null
          used_in_recipes: number | null
          verified: boolean | null
        }
        Relationships: []
      }
      line_grams: {
        Row: {
          food_id: string | null
          grams: number | null
          id: string | null
          quantity: number | null
          recipe_id: string | null
          unit: string | null
          via_estimate: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      line_priceability: {
        Row: {
          food_id: string | null
          id: string | null
          priced: boolean | null
          recipe_id: string | null
          unit: string | null
          via_estimate: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "food_leverage"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "ingredient_lines_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_effective_tags: {
        Row: {
          from_override: boolean | null
          kind: Database["public"]["Enums"]["tag_kind"] | null
          name: string | null
          recipe_id: string | null
          tag_id: string | null
        }
        Relationships: []
      }
      recipe_protein_families: {
        Row: {
          grams: number | null
          is_main: boolean | null
          protein_family: string | null
          protein_family_label: string | null
          recipe_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "foods_protein_family_fkey"
            columns: ["protein_family"]
            isOneToOne: false
            referencedRelation: "protein_families"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_readiness"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipe_verification"
            referencedColumns: ["recipe_id"]
          },
          {
            foreignKeyName: "ingredient_lines_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_readiness: {
        Row: {
          has_data_issue: boolean | null
          ready: boolean | null
          recipe_id: string | null
          title: string | null
          total_lines: number | null
          unpriced_lines: number | null
          unverified_foods: number | null
        }
        Relationships: []
      }
      recipe_verification: {
        Row: {
          ai_verified: boolean | null
          data_issue: string | null
          estimated_ingredients: string[] | null
          estimated_line_count: number | null
          has_image: boolean | null
          has_title: boolean | null
          line_count: number | null
          reasons: string[] | null
          recipe_id: string | null
          signed_at: string | null
          signed_by_name: string | null
          signoff_on_hold: boolean | null
          status: string | null
          step_count: number | null
          title: string | null
          uncalculable_ingredients: string[] | null
          uncalculable_line_count: number | null
          unverified_food_count: number | null
          unverified_food_names: string[] | null
        }
        Relationships: []
      }
    }
    Functions: {
      _intake_normalise: {
        Args: { p_key: string; p_value: Json }
        Returns: Json
      }
      _log_client_change: {
        Args: {
          p_action: string
          p_client_id: string
          p_field: string
          p_new: string
          p_old: string
        }
        Returns: undefined
      }
      _merge_client_records: {
        Args: { p_from: string; p_into: string }
        Returns: Json
      }
      add_my_result: {
        Args: {
          p_file_path: string
          p_kind: string
          p_note?: string
          p_recorded_on: string
        }
        Returns: Json
      }
      app_setting: { Args: { p_key: string }; Returns: string }
      can_access_client: { Args: { p_client_id: string }; Returns: boolean }
      can_access_plan: { Args: { p_plan_id: string }; Returns: boolean }
      can_view_checkins: { Args: { p_client_id: string }; Returns: boolean }
      change_log_fmt: { Args: { v: Json }; Returns: string }
      claim_client_invite: { Args: { p_token: string }; Returns: Json }
      client_app_signups: {
        Args: never
        Returns: {
          created_at: string
          email: string
          full_name: string
          phone: string
          user_id: string
        }[]
      }
      client_app_status: { Args: { p_client_id: string }; Returns: Json }
      client_energy_inputs: {
        Args: { p_as_of?: string; p_client_id: string }
        Returns: {
          activity_factor: number
          activity_key: string
          activity_label: string
          as_of: string
          client_id: string
          date_of_birth: string
          equation_sex: string
          height_cm: number
          protein_g_per_kg: number
          sex: string
          weighed_on: string
          weight_kg: number
        }[]
      }
      client_intake_for_staff: { Args: { p_client_id: string }; Returns: Json }
      client_recipe_screen: {
        Args: { p_client_id: string }
        Returns: {
          liked_protein: boolean
          main_protein_families: string[]
          preferred_tags: string[]
          reasons: string[]
          recipe_id: string
          status: string
        }[]
      }
      client_signup_queue: { Args: never; Returns: Json }
      client_tag_kind: { Args: { p_tag_id: string }; Returns: string }
      clinical_file_in_use: { Args: { p_path: string }; Returns: boolean }
      confirm_plan: {
        Args: { p_confirm?: boolean; p_notes?: string; p_plan_id: string }
        Returns: Json
      }
      credential_status: { Args: { p_due: string }; Returns: string }
      current_staff_role: { Args: never; Returns: string }
      delete_user: { Args: { target_id: string }; Returns: undefined }
      food_field_label: { Args: { k: string }; Returns: string }
      get_client_invitation: { Args: { p_token: string }; Returns: Json }
      get_invitation: {
        Args: { p_token: string }
        Returns: {
          email: string
          role: string
          valid: boolean
        }[]
      }
      intake_client_questions: {
        Args: { p_client_id: string }
        Returns: {
          help: string
          key: string
          kind: string
          label: string
          locked: boolean
          options: Json
          q_pos: number
          required: boolean
          s_pos: number
          section: string
        }[]
      }
      intake_missing: { Args: { p_client_id: string }; Returns: Json }
      invite_client_to_app: {
        Args: { p_client_id: string; p_email?: string }
        Returns: Json
      }
      is_admin: { Args: never; Returns: boolean }
      is_clinician: { Args: never; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      link_client_account: {
        Args: { p_client_id: string; p_user_id: string }
        Returns: Json
      }
      mark_changes_reviewed: { Args: { p_ids?: number[] }; Returns: number }
      mark_credential_checked: {
        Args: { p_checked: boolean; p_id: string }
        Returns: Json
      }
      merge_client_into: {
        Args: { p_from: string; p_into: string }
        Returns: Json
      }
      my_areas: { Args: never; Returns: Json }
      my_client_id: { Args: never; Returns: string }
      my_details: { Args: never; Returns: Json }
      my_intake: { Args: never; Returns: Json }
      my_plan_version: {
        Args: { p_plan_id: string; p_version_no?: number }
        Returns: Json
      }
      my_plans: {
        Args: never
        Returns: {
          days: number
          end_date: string
          is_current: boolean
          plan_id: string
          published_at: string
          start_date: string
          title: string
          version_no: number
        }[]
      }
      my_results: { Args: never; Returns: Json }
      plan_days: {
        Args: { p_plan_id: string }
        Returns: {
          carb_g: number
          date: string
          day: number
          day_type: string
          day_type_source: string
          fat_g: number
          fibre_g: number
          kcal: number
          protein_g: number
          targets_day_type: string
          weekday: string
        }[]
      }
      plan_publish_check: { Args: { p_plan_id: string }; Returns: Json }
      plan_slots: {
        Args: { p_plan_id: string }
        Returns: {
          free_choice: boolean
          name: string
          position: number
          slot_kind: string
          source: string
        }[]
      }
      publish_meal_plan: {
        Args: { p_plan_id: string; p_release_on?: string; p_snapshot: Json }
        Returns: Json
      }
      reason_list: {
        Args: { items: string[]; max_items?: number }
        Returns: string
      }
      remove_my_result: { Args: { p_id: string }; Returns: Json }
      reorder_intake: {
        Args: { p_questions: Json; p_sections: Json }
        Returns: Json
      }
      revoke_recipe_signoff: {
        Args: { p_note?: string; p_recipe_id: string }
        Returns: Json
      }
      save_client_intake_answers: {
        Args: { p_answers: Json; p_client_id: string }
        Returns: Json
      }
      save_client_structure: {
        Args: {
          p_client_id: string
          p_protein_spread: Json
          p_settings: Json
          p_slots: Json
        }
        Returns: undefined
      }
      save_my_intake: { Args: { p_changes: Json }; Returns: Json }
      set_client_intake_questions: {
        Args: { p_client_id: string; p_question_keys: string[] }
        Returns: Json
      }
      set_client_intake_status: {
        Args: { p_client_id: string; p_status: string }
        Returns: Json
      }
      set_my_show_numbers: { Args: { p_show: boolean }; Returns: Json }
      sign_off_recipe: { Args: { p_recipe_id: string }; Returns: Json }
      start_new_plan_version: { Args: { p_plan_id: string }; Returns: Json }
      submit_my_intake: { Args: never; Returns: Json }
      team_compliance: { Args: never; Returns: Json }
      unlink_client_account: { Args: { p_client_id: string }; Returns: Json }
      use_plan_alternative: { Args: { p_item_id: string }; Returns: Json }
    }
    Enums: {
      food_source: "afcd" | "custom"
      override_action: "add" | "remove"
      tag_kind: "allergen" | "dietary"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      food_source: ["afcd", "custom"],
      override_action: ["add", "remove"],
      tag_kind: ["allergen", "dietary"],
    },
  },
} as const
