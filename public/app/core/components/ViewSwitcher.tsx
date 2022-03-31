import React from 'react';

import { getBackendSrv } from '@grafana/runtime';
import { Modal, Button } from '@grafana/ui';

import { contextSrv } from 'app/core/services/context_srv';
import config from 'app/core/config';

interface Props {
  onDismiss: () => void;
}

export class ViewSwitcher extends React.PureComponent<Props> {
  setCurrentView = async (view: string) => {
    await getBackendSrv().post(`/api/user/view/${view}`);
    contextSrv.user.view = view;
    window.location.href = config.appUrl;
  };

  render() {
    const { onDismiss } = this.props;
    const { views } = config;
    const currentView = contextSrv.user.view;

    return (
      <Modal title="Switch View" icon="arrow-random" onDismiss={onDismiss} isOpen={true}>
        <table className="filter-table form-inline">
          <thead>
            <tr>
              <th>Name</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {views.map((view) => (
              <tr key={view}>
                <td>{view}</td>
                <td className="text-right">
                  {view === currentView ? (
                    <Button size="sm">Current</Button>
                  ) : (
                    <Button variant="secondary" size="sm" onClick={() => this.setCurrentView(view)}>
                      Switch to
                    </Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Modal>
    );
  }
}
