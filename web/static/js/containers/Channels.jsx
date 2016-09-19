import React, { Component } from 'react'
import { connect } from 'react-redux'
import * as actions from '../actions/channels'
import AddButton from '../components/AddButton'
import EmptyPage from '../components/EmptyPage'
import CardTable from '../components/CardTable'

class Channels extends Component {
  componentDidMount() {
    const { dispatch } = this.props;
    dispatch(actions.fetchChannels());
  }

  addChannel(event) {
    event.preventDefault()
    const { dispatch } = this.props
    dispatch(actions.createNuntiumChannel()).then(x => console.log(x))
  }

  render() {
    const { channels } = this.props
    const title = `${Object.keys(channels).length} ${(Object.keys(channels).length == 1) ? ' channel' : ' channels'}`

    return (
      <div>
        <AddButton text="Add channel" onClick={(e) => this.addChannel(e)} />
        { (Object.keys(channels).length == 0) ?
          <EmptyPage icon='assignment' title='You have no channels on this project' onClick={(e) => this.addChannel(e)} />
        :
          <CardTable title={ title }>
            <thead>
              <tr>
                <th>Name</th>
              </tr>
            </thead>
            <tbody>
              { Object.keys(channels).map(id =>
                <tr key={id}>
                  <td>{channels[id].name}</td>
                </tr>
              )}
            </tbody>
          </CardTable>
        }
      </div>
    )
  }
}

const mapStateToProps = (state) => ({
  channels: state.channels
})

export default connect(mapStateToProps)(Channels)