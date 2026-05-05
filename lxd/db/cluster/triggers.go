package cluster

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/canonical/lxd/shared/entity"
)

// applyTriggers adds triggers to the database.
//
// Warning: These triggers are applied separately to the schema update mechanism. Changes to these triggers (especially their names)
// may require a patch.
func applyTriggers(ctx context.Context, tx *sql.Tx) error {
	applyTrigger := func(name string, stmt string, entityType entity.Type) error {
		if name == "" && stmt == "" {
			return nil
		} else if name == "" || stmt == "" {
			return fmt.Errorf("Trigger name or SQL missing for entity type %q", entityType)
		}

		_, err := tx.ExecContext(ctx, "DROP TRIGGER IF EXISTS "+name)
		if err != nil {
			return err
		}

		_, err = tx.ExecContext(ctx, stmt)
		if err != nil {
			return err
		}

		return nil
	}

	for entityType, entityTypeInfo := range entityTypes {
		name, stmt := entityTypeInfo.onDeleteTriggerSQL()
		err := applyTrigger(name, stmt, entityType)
		if err != nil {
			return err
		}

		name, stmt = entityTypeInfo.onUpdateTriggerSQL()
		err = applyTrigger(name, stmt, entityType)
		if err != nil {
			return err
		}

		name, stmt = entityTypeInfo.onInsertTriggerSQL()
		err = applyTrigger(name, stmt, entityType)
		if err != nil {
			return err
		}
	}

	return nil
}
