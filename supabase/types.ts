export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
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
      clients: {
        Row: {
          carb_target_g: number | null
          created_at: string
          email: string | null
          fat_target_g: number | null
          fibre_target_g: number | null
          full_name: string
          id: string
          kcal_target: number | null
          notes: string | null
          phone: string | null
          protein_target_g: number | null
          restrictions: string[]
        }
        Insert: {
          carb_target_g?: number | null
          created_at?: string
          email?: string | null
          fat_target_g?: number | null
          fibre_target_g?: number | null
          full_name: string
          id?: string
          kcal_target?: number | null
          notes?: string | null
          phone?: string | null
          protein_target_g?: number | null
          restrictions?: string[]
        }
        Update: {
          carb_target_g?: number | null
          created_at?: string
          email?: string | null
          fat_target_g?: number | null
          fibre_target_g?: number | null
          full_name?: string
          id?: string
          kcal_target?: number | null
          notes?: string | null
          phone?: string | null
          protein_target_g?: number | null
          restrictions?: string[]
        }
        Relationships: []
      }
      food_diet_flags: {
        Row: {
          flag: string
          food_id: string
          source: string
        }
        Insert: {
          flag: string
          food_id: string
          source?: string
        }
        Update: {
          flag?: string
          food_id?: string
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_diet_flags_food_id_fkey"
            columns: ["food_id"]
            isOneToOne: false
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
        ]
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
          satfat_100g?: number | null
          sodium_100g?: number | null
          source?: Database["public"]["Enums"]["food_source"]
          sugars_100g?: number | null
          verified?: boolean
          vitamin_b12_100g?: number | null
          zinc_100g?: number | null
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
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
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
      invitations: {
        Row: {
          accepted_at: string | null
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
          created_at?: string
          email?: string
          expires_at?: string | null
          id?: string
          invited_by?: string | null
          role?: string
          token?: string
        }
        Relationships: []
      }
      meal_plan_items: {
        Row: {
          day: number | null
          id: string
          meal_plan_id: string
          meal_slot: string | null
          position: number
          recipe_id: string
          servings_override: number | null
        }
        Insert: {
          day?: number | null
          id?: string
          meal_plan_id: string
          meal_slot?: string | null
          position: number
          recipe_id: string
          servings_override?: number | null
        }
        Update: {
          day?: number | null
          id?: string
          meal_plan_id?: string
          meal_slot?: string | null
          position?: number
          recipe_id?: string
          servings_override?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "meal_plan_items_meal_plan_id_fkey"
            columns: ["meal_plan_id"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
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
      meal_plans: {
        Row: {
          client_id: string | null
          created_at: string
          days: number | null
          id: string
          notes: string | null
          title: string
        }
        Insert: {
          client_id?: string | null
          created_at?: string
          days?: number | null
          id?: string
          notes?: string | null
          title: string
        }
        Update: {
          client_id?: string | null
          created_at?: string
          days?: number | null
          id?: string
          notes?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_plans_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
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
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          job_title: string | null
          organisation: string | null
          phone: string | null
          role: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          id: string
          job_title?: string | null
          organisation?: string | null
          phone?: string | null
          role?: string
        }
        Update: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          job_title?: string | null
          organisation?: string | null
          phone?: string | null
          role?: string
        }
        Relationships: []
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
          food_id: string
          grams: number
          id: number
          unit: string
        }
        Insert: {
          basis?: string | null
          food_id: string
          grams: number
          id?: never
          unit: string
        }
        Update: {
          basis?: string | null
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
            referencedRelation: "foods"
            referencedColumns: ["food_id"]
          },
        ]
      }
    }
    Views: {
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
    }
    Functions: {
      delete_user: { Args: { target_id: string }; Returns: undefined }
      get_invitation: {
        Args: { p_token: string }
        Returns: {
          email: string
          role: string
          valid: boolean
        }[]
      }
      is_admin: { Args: never; Returns: boolean }
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      food_source: ["afcd", "custom"],
      override_action: ["add", "remove"],
      tag_kind: ["allergen", "dietary"],
    },
  },
} as const

